/**
 * Regression tests for enabling audio before the reader view mounts.
 *
 * On web the reader widget owns the `#container` the visual navigators render into, so a
 * text publication is only "opened" on the JS side once that widget mounts. Audio needs no
 * container, so audioEnable must work from the moment the publication is loaded, and the
 * later open must not stop what is already narrating.
 */
import { Link, Links, Locator, LocatorLocations } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

jest.mock("../navigators/FlutterMediaOverlayNavigator", () => ({
  ...jest.requireActual("../navigators/FlutterMediaOverlayNavigator"),
  initializeGuidedNavigationNavigator: jest.fn(),
}));
jest.mock("../navigators/FlutterEpubNavigator", () => ({
  ...jest.requireActual("../navigators/FlutterEpubNavigator"),
  FlutterEpubNavigator: { create: jest.fn() },
}));

import { initializeGuidedNavigationNavigator } from "../navigators/FlutterMediaOverlayNavigator";
import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;

/** EPUB with a guided-navigation alternate on its only reading-order item. */
function guidedNavPublication(): ReadiumPublication {
  return {
    baseURL: "https://example.test/book/",
    conformsToAudiobook: false,
    conformsToEpub: true,
    conformsToDivina: false,
    metadata: { identifier: "urn:test:book" },
    readingOrder: {
      items: [
        new Link({
          href: "chapter1.xhtml",
          alternates: new Links([
            new Link({ href: "chapter1-guided.json", type: "application/guided-navigation+json" }),
          ]),
        }),
      ],
    },
    resources: { items: [] },
    manifest: { links: undefined, toc: undefined },
  } as unknown as ReadiumPublication;
}

function textLocator(fragment: string): Locator {
  return new Locator({
    href: "chapter1.xhtml",
    type: "application/xhtml+xml",
    locations: new LocatorLocations({ fragments: [fragment] }),
  });
}

/** DiViNa comic: a publication-level guided document and image reading-order items. */
function divinaPublication(): ReadiumPublication {
  return {
    baseURL: "https://example.test/comic/",
    conformsToAudiobook: false,
    conformsToEpub: false,
    conformsToDivina: true,
    metadata: { identifier: "urn:test:comic" },
    readingOrder: {
      items: [new Link({ href: "image0001.jpg" }), new Link({ href: "image0002.jpg" })],
    },
    resources: { items: [] },
    manifest: {
      links: new Links([
        new Link({ href: "guided-navigation.json", type: "application/guided-navigation+json" }),
      ]),
      toc: undefined,
    },
  } as unknown as ReadiumPublication;
}

function comicLocator(href: string): Locator {
  return new Locator({
    href,
    type: "text/html",
    locations: new LocatorLocations({
      fragments: [],
      otherLocations: new Map<string, any>([["comicRegion", { x: 1, y: 2, w: 3, h: 4 }]]),
    }),
  });
}

function fakeComicNav() {
  return {
    go: jest.fn((_l: Locator, _a: boolean, cb?: (ok: boolean) => void) => cb?.(true)),
    panToRegion: jest.fn(),
    setAutoPan: jest.fn(),
    destroy: jest.fn(),
  };
}

function fakeAudioNav() {
  return {
    currentLocator: textLocator("p1"),
    stop: jest.fn(),
    destroy: jest.fn(),
    play: jest.fn(),
    go: jest.fn((_l: Locator, _a: boolean, cb?: (ok: boolean) => void) => cb?.(true)),
  };
}

describe("audio before the reader view mounts", () => {
  let savedWindow: any;
  let savedDocument: any;

  beforeEach(() => {
    savedWindow = (globalThis as any).window;
    savedDocument = (globalThis as any).document;
    (globalThis as any).window = { updateReaderStatus: jest.fn() };
    (globalThis as any).document = {
      getElementById: () => null,
      body: { querySelector: () => ({ innerHTML: "" }) },
    };
  });

  afterEach(() => {
    if (savedWindow === undefined) delete (globalThis as any).window;
    else (globalThis as any).window = savedWindow;
    if (savedDocument === undefined) delete (globalThis as any).document;
    else (globalThis as any).document = savedDocument;
    jest.restoreAllMocks();
    jest.clearAllMocks();
  });

  it("flags guided navigation while loading the publication, before any open", async () => {
    const reader = new ReadiumReader();
    const publication = guidedNavPublication();
    (reader as any)._pubManager = {
      fetchAndCache: jest.fn().mockResolvedValue({ publication, manifestJson: "{}" }),
    };

    await reader.getPublication("https://example.test/book/manifest.json");

    expect((reader as any)._hasGuidedNavigation).toBe(true);
    expect((reader as any)._nav).toBeUndefined();
  });

  it("builds the audio navigator with no visual navigator and no container", async () => {
    const reader = new ReadiumReader();
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    const audioNav = fakeAudioNav();
    (initializeGuidedNavigationNavigator as jest.Mock).mockImplementation(
      async (_pub, _loc, _prefs, setNav) => setNav(audioNav, [])
    );
    (reader as any)._publication = guidedNavPublication();
    (reader as any)._hasGuidedNavigation = true;

    await reader.audioEnable('{"speed":1.0}', undefined);

    expect(initializeGuidedNavigationNavigator).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNav).toBe(audioNav);
    expect(warn).not.toHaveBeenCalled();
  });

  it("keeps the narrating audio navigator when the reader view opens the same publication", async () => {
    const reader = new ReadiumReader();
    const publication = guidedNavPublication();
    const audioNav = fakeAudioNav();
    (reader as any)._publication = publication;
    (reader as any)._audioNav = audioNav;
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(publication) };
    (FlutterEpubNavigator.create as jest.Mock).mockImplementation(
      async (_c, _p, _i, _prefs, setNav) => setNav({ destroy: jest.fn() })
    );

    await reader.openPublication("https://example.test/book/manifest.json", "urn:test:book", undefined, "{}", "[]");

    expect(audioNav.stop).not.toHaveBeenCalled();
    expect(audioNav.destroy).not.toHaveBeenCalled();
    expect((reader as any)._audioNav).toBe(audioNav);
  });

  it("still tears audio down when a different publication is opened", async () => {
    const reader = new ReadiumReader();
    const audioNav = fakeAudioNav();
    (reader as any)._publication = guidedNavPublication();
    (reader as any)._audioNav = audioNav;
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(guidedNavPublication()) };
    (FlutterEpubNavigator.create as jest.Mock).mockImplementation(
      async (_c, _p, _i, _prefs, setNav) => setNav({ destroy: jest.fn() })
    );

    await reader.openPublication("https://example.test/other/manifest.json", "urn:test:other", undefined, "{}", "[]");

    expect(audioNav.stop).toHaveBeenCalledTimes(1);
    expect(audioNav.destroy).toHaveBeenCalledTimes(1);
  });

  it("enables audio straight after getPublication, with no open in between", async () => {
    const reader = new ReadiumReader();
    const publication = guidedNavPublication();
    (reader as any)._pubManager = {
      fetchAndCache: jest.fn().mockResolvedValue({ publication, manifestJson: "{}" }),
    };
    const audioNav = fakeAudioNav();
    (initializeGuidedNavigationNavigator as jest.Mock).mockImplementation(
      async (_pub, _loc, _prefs, setNav) => setNav(audioNav, [])
    );

    // The sequence every client follows: await openPublication, then audioEnable.
    // getPublication is the part of that which the JS side sees.
    await reader.getPublication("https://example.test/book/manifest.json");
    await reader.audioEnable('{"speed":1.0}', undefined);

    expect(initializeGuidedNavigationNavigator).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNav).toBe(audioNav);
  });

  it("refuses audioEnable before the publication is loaded instead of deferring it", async () => {
    const reader = new ReadiumReader();
    const error = jest.spyOn(console, "error").mockImplementation(() => {});

    await reader.audioEnable('{"speed":1.0}', undefined);

    expect(initializeGuidedNavigationNavigator).not.toHaveBeenCalled();
    expect((reader as any)._audioNav).toBeUndefined();
    expect(error).toHaveBeenCalled();
  });

  it("replays the cue that narrated before the visual navigator existed", async () => {
    const reader = new ReadiumReader();
    const audioNav = fakeAudioNav();
    (reader as any)._audioNav = audioNav;

    // Cue emitted while no visual navigator exists: remembered, not applied.
    (reader as any)._syncVisualToMediaOverlayLocator(textLocator("p7"), "GuidedNavigation", 1200);
    expect((reader as any)._lastDeferredSyncLocator?.locations?.fragments?.[0]).toBe("p7");

    const nav = { go: jest.fn((_l: Locator, _a: boolean, cb?: (ok: boolean) => void) => cb?.(true)) };
    (reader as any)._nav = nav;
    (reader as any)._replayDeferredVisualSync();

    expect(nav.go).toHaveBeenCalledTimes(1);
    expect((nav.go.mock.calls[0][0] as Locator).locations?.fragments?.[0]).toBe("p7");
  });

  it("sends comic cues to the comic navigator that mounts after audio started", async () => {
    const reader = new ReadiumReader();
    const audioNav = fakeAudioNav();
    let emitCue: ((locator: Locator, durationMs?: number) => void) | undefined;
    (initializeGuidedNavigationNavigator as jest.Mock).mockImplementation(
      async (_pub, _loc, _prefs, setNav, onCue) => {
        setNav(audioNav, []);
        emitCue = onCue;
      }
    );
    (reader as any)._publication = divinaPublication();
    (reader as any)._hasGuidedNavigation = true;

    await reader.audioEnable('{"speed":1.0}', undefined);
    expect(emitCue).toBeDefined();

    // Narration runs before the reader view exists, so this cue has nowhere to go.
    emitCue!(comicLocator("image0001.jpg"), 900);

    const comicNav = fakeComicNav();
    (reader as any)._comicNav = comicNav;
    emitCue!(comicLocator("image0002.jpg"), 900);

    expect(comicNav.go).toHaveBeenCalledTimes(1);
    expect((comicNav.go.mock.calls[0][0] as Locator).href).toBe("image0002.jpg");
    expect(comicNav.panToRegion).toHaveBeenCalledWith({ x: 1, y: 2, w: 3, h: 4 });
  });

  it("replays the comic cue that narrated before the comic navigator existed", () => {
    const reader = new ReadiumReader();
    (reader as any)._audioNav = fakeAudioNav();

    (reader as any)._routeNarrationCue(comicLocator("image0002.jpg"), "GuidedNavigation", 900);

    const comicNav = fakeComicNav();
    (reader as any)._comicNav = comicNav;
    (reader as any)._replayDeferredVisualSync();

    expect(comicNav.go).toHaveBeenCalledTimes(1);
    expect((comicNav.go.mock.calls[0][0] as Locator).href).toBe("image0002.jpg");
  });
});
