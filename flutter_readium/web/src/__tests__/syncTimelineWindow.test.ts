/**
 * Streaming lazy window regression tests (on top of PR #311):
 *  - fillAhead is position-bound: a backward jump refills the budget ahead of
 *    the NEW playhead instead of being starved by the old forward window.
 *  - A transiently failed segment is retried in place and never burns budget
 *    (ADR 0003 "honest end": one flaky pass must not end the book).
 *  - takeOverAtEdge concedes "ended" when the window extension it joined
 *    failed, instead of swallowing the event.
 */

import { Link, Links, Locator } from "@readium/shared";
import { SyncTimelineStore } from "../mediaoverlay/syncTimeline";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import { initializeMediaOverlayNavigator, MediaOverlaySession } from "../navigators/FlutterMediaOverlayNavigator";

const BASE = "https://example.test/book/";

function chapterLink(i: number): Link {
  return new Link({
    href: `chap${i}.xhtml`,
    type: "application/xhtml+xml",
    duration: 20,
    alternates: new Links([
      new Link({ href: `chap${i}.json`, type: "application/vnd.readium.narration+json" }),
    ]),
  });
}

function narrationDoc(i: number): unknown {
  return {
    narration: [
      { audio: `chap${i}.mp3#t=0,10`, text: `chap${i}.xhtml#p1` },
      { audio: `chap${i}.mp3#t=10,20`, text: `chap${i}.xhtml#p2` },
    ],
  };
}

function publicationWithChapters(
  count: number,
  opts: { failOnce?: (href: string) => boolean } = {}
): { publication: ReadiumPublication; fetches: string[] } {
  const readingOrder = Array.from({ length: count }, (_, i) => chapterLink(i + 1));
  const fetches: string[] = [];
  const get = jest.fn((link: Link) => {
    fetches.push(link.href);
    return {
      readAsJSON: async () => {
        const m = link.href.match(/chap(\d+)\.json$/);
        if (!m) throw new Error(`unexpected fetch ${link.href}`);
        if (opts.failOnce?.(link.href)) throw new Error(`simulated failure ${link.href}`);
        return narrationDoc(parseInt(m[1], 10));
      },
    };
  });
  const publication = {
    baseURL: BASE,
    readingOrder: { items: readingOrder },
    manifest: {
      toc: new Links([]),
      serialize: () => ({ metadata: { title: "Test", duration: count * 20 } }),
      linksWithRel: () => [new Link({ href: `${BASE}manifest.json` })],
    },
    get,
  } as unknown as ReadiumPublication;
  return { publication, fetches };
}

function chapLocator(i: number): Locator {
  return new Locator({ href: `chap${i}.xhtml`, type: "application/xhtml+xml" });
}

describe("SyncTimelineStore lookahead budget", () => {
  it("refills ahead of the NEW playhead after a backward jump", async () => {
    const { publication, fetches } = publicationWithChapters(100);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    // Simulate playback reaching chapter 50: the window covered 49..52.
    await store.loadSegment(49);
    await store.fillAhead(49);
    expect(store.loadedTailIndex()).toBe(52);

    // Jump back to chapter 5 (roIndex 4); the seek path fetches only the target.
    expect(await store.ensureSegmentForText("chap5.xhtml")).toBe(true);

    // The tick lookahead must fill the K slots ahead of the new playhead —
    // not be starved by segments loaded ahead of the OLD position.
    fetches.length = 0;
    await store.fillAhead(4);
    expect(fetches).toEqual(["chap6.json", "chap7.json", "chap8.json"]);

    // Merged order (= rebuilt playlist): the jump target is followed by its
    // own neighbours, not by the old forward window.
    const order = [...new Set(store.items().map((i) => i.audioHref))];
    expect(order.slice(0, 4)).toEqual(["chap5.mp3", "chap6.mp3", "chap7.mp3", "chap8.mp3"]);
  });

  it("retries a transiently failed segment in place without burning budget", async () => {
    const flaky = new Set(["chap6.json"]);
    const { publication, fetches } = publicationWithChapters(100, {
      failOnce: (href) => {
        if (flaky.has(href)) {
          flaky.delete(href);
          return true;
        }
        return false;
      },
    });
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    await store.loadSegment(4); // chap5 is the playhead
    fetches.length = 0;
    await store.fillAhead(4);
    // chap6 failed once and was retried in place; the full K=3 window still lands.
    expect(store.isLoaded(5)).toBe(true);
    expect(store.isLoaded(6)).toBe(true);
    expect(store.isLoaded(7)).toBe(true);
    expect(fetches.filter((h) => h === "chap6.json")).toHaveLength(2);
  });

  it("exhausts a permanently failing slot without wedging the window", async () => {
    const { publication } = publicationWithChapters(10, {
      failOnce: (href) => href === "chap6.json", // always fails: both attempts
    });
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    await store.loadSegment(4);
    await store.fillAhead(4);
    // chap6 hit the 2-failure cap; budget moved on: chap7 and chap8 loaded.
    expect(store.isLoaded(5)).toBe(false);
    expect(store.isLoaded(6)).toBe(true);
    expect(store.isLoaded(7)).toBe(true);
  });
});

describe("MediaOverlaySession edge takeover honesty", () => {
  afterEach(() => jest.restoreAllMocks());

  function fakeNav(href: string) {
    return {
      currentLocator: new Locator({ href, type: "audio/mpeg" }),
      isPlaying: false,
      currentTime: 0,
      duration: 20,
      stop: jest.fn(),
      destroy: jest.fn(),
      play: jest.fn(),
    };
  }

  function mockCreateAlways(navHref: string) {
    jest.spyOn(FlutterAudioNavigator, "create").mockImplementation(
      (async (_pub: unknown, _init: unknown, _prefs: unknown, setNav: unknown) => {
        (setNav as (n: unknown) => void)(fakeNav(navHref));
      }) as never
    );
  }

  /** Test seam: the private in-flight extension that takeOverAtEdge joins. */
  type SessionInternals = { rebuild?: Promise<void> };

  /** Assign a rebuild that failed, clearing the slot like production's finally does. */
  function injectFailedRebuild(session: MediaOverlaySession): void {
    const internals = session as unknown as SessionInternals;
    internals.rebuild = Promise.reject(new Error("simulated rebuild failure")).catch((err) => {
      internals.rebuild = undefined;
      throw err;
    });
  }

  it("concedes ended when the joined rebuild failed and no successor can load", async () => {
    mockCreateAlways(`${BASE}chap1.mp3`);
    // chap2 permanently fails: the only successor is unreachable.
    const { publication } = publicationWithChapters(2, {
      failOnce: (href) => href === "chap2.json",
    });
    const session = await initializeMediaOverlayNavigator(
      publication, chapLocator(1), "{}", jest.fn()
    );

    injectFailedRebuild(session!);
    // Startup loaded only chap1; the edge tries chap2 (exhausted) then ends
    // honestly instead of wedging.
    expect(await session!.takeOverAtEdge()).toBe(false);
  });

  it("takes over when the joined rebuild failed but a successor can load", async () => {
    mockCreateAlways(`${BASE}chap4.mp3`);
    const { publication } = publicationWithChapters(10);
    const session = await initializeMediaOverlayNavigator(
      publication, chapLocator(1), "{}", jest.fn()
    );

    injectFailedRebuild(session!);
    // chap2.. are still loadable: the edge is a takeover, not an end.
    expect(await session!.takeOverAtEdge()).toBe(true);
  });
});
