/**
 * Streaming lazy timeline tests:
 *  - SyncTimelineStore loads exactly one JSON per segment, in RO order.
 *  - Navigating ("seeking") to a lazy-loaded part of the publication fetches
 *    only the target segment and makes its cues + audio track available.
 *  - The eager fallback kicks in when the store can't cover the publication.
 */

import { Link, Links, Locator } from "@readium/shared";
import { SyncTimelineStore } from "../mediaoverlay/syncTimeline";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import { initializeMediaOverlayNavigator } from "../navigators/FlutterMediaOverlayNavigator";

const BASE = "https://example.test/book/";

function chapterLink(i: number, duration: number): Link {
  return new Link({
    href: `chap${i}.xhtml`,
    type: "application/xhtml+xml",
    duration,
    alternates: new Links([
      new Link({
        href: `chap${i}.json`,
        type: "application/vnd.readium.narration+json",
      }),
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

function publicationWithChapters(count: number): {
  publication: ReadiumPublication;
  get: jest.Mock;
  fetches: string[];
} {
  const readingOrder = Array.from({ length: count }, (_, i) => chapterLink(i + 1, 20));
  const fetches: string[] = [];
  const get = jest.fn((link: Link) => {
    fetches.push(link.href);
    return {
      readAsJSON: async () => {
        const m = link.href.match(/chap(\d+)\.json$/);
        if (!m) throw new Error(`unexpected fetch ${link.href}`);
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
  return { publication, get, fetches };
}

describe("SyncTimelineStore", () => {
  it("resolves segments without fetching anything", () => {
    const { publication, fetches } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    expect(store).not.toBeNull();
    expect(store.segmentIndexes()).toEqual([0, 1, 2, 3]);
    expect(fetches).toEqual([]);
  });

  it("loadSegment fetches exactly one JSON", async () => {
    const { publication, fetches } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    const items = await store.loadSegment(0);
    expect(fetches).toEqual(["chap1.json"]);
    expect(items).toHaveLength(2);
    expect(items![0].position).toBe(0);
    expect(items!.map((i) => i.audioHref)).toEqual(["chap1.mp3", "chap1.mp3"]);
  });

  it("items() lists loaded cues in reading-order position", async () => {
    const { publication } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    await store.loadSegment(2);
    await store.loadSegment(0);
    const items = store.items();
    expect(items.map((i) => i.position)).toEqual([0, 0, 2, 2]);
  });

  it("prepareWindow loads the initial segment and looks ahead K segments", async () => {
    const { publication, fetches } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    const items = await store.prepareWindow(0);
    // prepareWindow returns the initial segment immediately...
    expect(items).toHaveLength(2);
    await store.settle();
    // ...while the lookahead (K=3) fills the rest: all 4 segments = 8 cues.
    expect(store.items()).toHaveLength(8);
    // Idempotent: repeated calls from the same playhead fetch nothing more.
    fetches.length = 0;
    await store.fillAhead(0);
    await store.fillAhead(0);
    expect(fetches).toHaveLength(0);
  });

  it("ensureSegmentForText fetches only the target segment", async () => {
    const { publication, fetches } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    await store.loadSegment(0);
    fetches.length = 0;
    const ok = await store.ensureSegmentForText("chap4.xhtml");
    expect(ok).toBe(true);
    expect(fetches).toEqual(["chap4.json"]);
    expect(store.items().some((i) => i.textHref === "chap4.xhtml")).toBe(true);
  });

  it("skips a segment after two failed loads and keeps others loadable", async () => {
    const { publication, get } = publicationWithChapters(4);
    get.mockImplementation((link: Link) => {
      if (link.href === "chap2.json") {
        return { readAsJSON: async () => { throw new Error("boom"); } };
      }
      return { readAsJSON: async () => narrationDoc(9) };
    });
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    expect(await store.loadSegment(1)).toBeNull();
    expect(await store.loadSegment(1)).toBeNull();
    expect(store.nextLoadableSegment(1)).toBe(2);
    expect(await store.loadSegment(2)).not.toBeNull();
  });

  it("returns null for a publication without alternates", () => {
    const publication = {
      baseURL: BASE,
      readingOrder: { items: [new Link({ href: "a.xhtml", type: "text/html" })] },
      manifest: { toc: new Links([]) },
      get: jest.fn(),
    } as unknown as ReadiumPublication;
    expect(SyncTimelineStore.forPublication(publication, "syncNarration")).toBeNull();
  });

  it("book totals come from metadata.duration without fetching", async () => {
    const { publication, fetches } = publicationWithChapters(4);
    const store = SyncTimelineStore.forPublication(publication, "syncNarration")!;
    expect(store.totalDurationSecs()).toBe(80);
    expect(await store.cumulativeBefore(2)).toBe(40);
    expect(fetches).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Session-level lazy navigation (navigate to lazy-loaded parts)
// ---------------------------------------------------------------------------

describe("MediaOverlaySession lazy window", () => {
  afterEach(() => jest.restoreAllMocks());

  it("startup loads a bounded window; navigating to a lazy chapter fetches only that segment and rebuilds", async () => {
    const create = jest.spyOn(FlutterAudioNavigator, "create");
    const created: Locator[][] = [];
    const fakeNav = {
      currentLocator: new Locator({ href: `${BASE}chap1.mp3`, type: "audio/mpeg" }),
      isPlaying: false,
      currentTime: 0,
      duration: 20,
      stop: jest.fn(),
      destroy: jest.fn(),
      play: jest.fn(),
    };
    create.mockImplementation(
      (async (_pub: unknown, initial: unknown, _prefs: unknown, setNav: unknown) => {
        created.push([initial as Locator]);
        (setNav as (n: unknown) => void)(fakeNav);
      }) as never
    );

    // 10 chapters; the window (K=3 ahead) can only cover 4 at startup.
    const { publication, fetches } = publicationWithChapters(10);
    const setNav = jest.fn();
    const session = await initializeMediaOverlayNavigator(
      publication,
      new Locator({ href: "chap1.xhtml", type: "application/xhtml+xml" }),
      "{}",
      setNav
    );
    expect(session).toBeDefined();
    await session!.settle();
    expect([...fetches].sort()).toEqual([
      "chap1.json", "chap2.json", "chap3.json", "chap4.json",
    ]);
    expect(created).toHaveLength(1);

    // Navigate to chapter 10 — deep in the lazy part of the book.
    fetches.length = 0;
    await session!.ensureWindowForText("chap10.xhtml");
    expect(fetches).toEqual(["chap10.json"]); // only the target segment fetched

    // The live setNav item array (what ReadiumReader holds as _syncItems)
    // gained the chapter-10 cues in place.
    const items = setNav.mock.calls.at(-1)![1] as { textHref: string }[];
    expect(items.some((i) => i.textHref === "chap10.xhtml")).toBe(true);
    // And the navigator was rebuilt with the extended playlist, resuming at the
    // current audio locator.
    expect(created.length).toBe(2);
    expect(created[1][0]?.href).toBe(`${BASE}chap1.mp3`);
  });

  it("falls back to the eager parse when the store finds no segments", async () => {
    const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
    const publication = {
      baseURL: BASE,
      readingOrder: { items: [new Link({ href: "a.xhtml", type: "text/html" })] },
      manifest: {
        toc: new Links([]),
        serialize: () => ({ metadata: {} }),
        linksWithRel: () => [],
      },
      // No alternates → store is null → parseSyncNarration runs (finds nothing).
      get: jest.fn(),
    } as unknown as ReadiumPublication;
    const session = await initializeMediaOverlayNavigator(
      publication,
      undefined,
      "{}",
      jest.fn()
    );
    expect(session).toBeUndefined();
    expect(create).not.toHaveBeenCalled();
  });

  it("takeOverAtEdge extends the window instead of ending while segments remain", async () => {
    const create = jest.spyOn(FlutterAudioNavigator, "create");
    const fakeNav = {
      // Playhead at the tail of the loaded window (chap4 of 10) — the real edge.
      currentLocator: new Locator({ href: `${BASE}chap4.mp3`, type: "audio/mpeg" }),
      isPlaying: false, currentTime: 0, duration: 20,
      stop: jest.fn(), destroy: jest.fn(), play: jest.fn(),
    };
    const created: Locator[][] = [];
    create.mockImplementation(
      (async (_pub: unknown, initial: unknown, _prefs: unknown, setNav: unknown) => {
        created.push([initial as Locator]);
        (setNav as (n: unknown) => void)(fakeNav);
      }) as never
    );
    // 10 chapters; startup window covers only the first 4.
    const { publication } = publicationWithChapters(10);
    const session = await initializeMediaOverlayNavigator(
      publication,
      new Locator({ href: "chap1.xhtml", type: "application/xhtml+xml" }),
      "{}",
      jest.fn()
    );
    await session!.settle();
    // The edge of the *playlist* is chap4; take-over must load beyond it and
    // resume at the current audio locator.
    expect(await session!.takeOverAtEdge()).toBe(true);
    expect(created).toHaveLength(2);
    expect(created[1][0]?.href).toBe(`${BASE}chap4.mp3`);
  });

  it("takeOverAtEdge concedes an honest end once the timeline is exhausted", async () => {
    const create = jest.spyOn(FlutterAudioNavigator, "create");
    const fakeNav = {
      currentLocator: new Locator({ href: `${BASE}chap1.mp3`, type: "audio/mpeg" }),
      isPlaying: false, currentTime: 0, duration: 20,
      stop: jest.fn(), destroy: jest.fn(), play: jest.fn(),
    };
    create.mockImplementation(
      (async (_pub: unknown, _initial: unknown, _prefs: unknown, setNav: unknown) => {
        (setNav as (n: unknown) => void)(fakeNav);
      }) as never
    );
    // 2-chapter book: startup window covers everything.
    const { publication } = publicationWithChapters(2);
    const session = await initializeMediaOverlayNavigator(
      publication,
      new Locator({ href: "chap1.xhtml", type: "application/xhtml+xml" }),
      "{}",
      jest.fn()
    );
    await session!.settle();
    expect(await session!.takeOverAtEdge()).toBe(false);
  });
});
