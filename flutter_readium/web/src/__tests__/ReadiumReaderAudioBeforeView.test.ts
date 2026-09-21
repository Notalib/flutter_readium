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
jest.mock("../navigators/FlutterAudioNavigator", () => ({
  ...jest.requireActual("../navigators/FlutterAudioNavigator"),
  setAudioEmissionsEnabled: jest.fn(),
  FlutterAudioNavigator: {
    create: jest.fn(),
    resetRecovery: jest.fn(),
    retryAfterFailure: jest.fn(),
    setPlaybackIntent: jest.fn(),
    isTerminallyFailed: jest.fn(() => false),
  },
}));

import { initializeGuidedNavigationNavigator } from "../navigators/FlutterMediaOverlayNavigator";
import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";
import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import { ReadiumWebErrorCode } from "../errors/ReadiumWebError";
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

/** Plain audiobook: no text documents, the AudioNavigator is built by openPublication. */
function audiobookPublication(): ReadiumPublication {
  return {
    baseURL: "https://example.test/audiobook/",
    conformsToAudiobook: true,
    conformsToEpub: false,
    conformsToDivina: false,
    metadata: { identifier: "urn:test:audiobook" },
    readingOrder: { items: [new Link({ href: "track1.mp3", type: "audio/mpeg" })] },
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

  it("discards an audio navigator whose publication changed while it was being created", async () => {
    const reader = new ReadiumReader();
    const requestedPublication = guidedNavPublication();
    const nextPublication = guidedNavPublication();
    const staleNav = fakeAudioNav();
    let finishCreate: (() => void) | undefined;
    (initializeGuidedNavigationNavigator as jest.Mock).mockImplementation(
      async (_pub, _loc, _prefs, setNav) =>
        new Promise<void>((resolve) => {
          finishCreate = () => {
            setNav(staleNav, []);
            resolve();
          };
        })
    );
    (reader as any)._publication = requestedPublication;
    (reader as any)._hasGuidedNavigation = true;

    const enable = reader.audioEnable('{"speed":1.0}', undefined);
    (reader as any)._publication = nextPublication;
    finishCreate!();
    await enable;

    expect(staleNav.stop).toHaveBeenCalledTimes(1);
    expect(staleNav.destroy).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNav).toBeUndefined();
    expect((reader as any)._audioNavPublication).toBeUndefined();
  });

  it("keeps the narrating audio navigator when the reader view opens the same publication", async () => {
    const reader = new ReadiumReader();
    const publication = guidedNavPublication();
    const audioNav = fakeAudioNav();
    (reader as any)._publication = publication;
    (reader as any)._audioNav = audioNav;
    (reader as any)._audioNavPublication = publication;
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
    const narrating = guidedNavPublication();
    (reader as any)._publication = narrating;
    (reader as any)._audioNav = audioNav;
    (reader as any)._audioNavPublication = narrating;
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(guidedNavPublication()) };
    (FlutterEpubNavigator.create as jest.Mock).mockImplementation(
      async (_c, _p, _i, _prefs, setNav) => setNav({ destroy: jest.fn() })
    );

    await reader.openPublication("https://example.test/other/manifest.json", "urn:test:other", undefined, "{}", "[]");

    expect(audioNav.stop).toHaveBeenCalledTimes(1);
    expect(audioNav.destroy).toHaveBeenCalledTimes(1);
  });

  it("stops narration when the open is for another book that loaded over the narrating one", async () => {
    // getPublication assigns _publication before the reader view mounts, so publication
    // identity alone cannot tell whether the running navigator belongs to this open.
    const reader = new ReadiumReader();
    const narrating = guidedNavPublication();
    const opening = guidedNavPublication();
    const audioNav = fakeAudioNav();
    (reader as any)._audioNav = audioNav;
    (reader as any)._audioNavPublication = narrating;
    (reader as any)._syncItems = [{ audio: "a.mp3", text: "chapter1.xhtml#p1" }];
    // What getPublication leaves behind: a fresh instance already installed.
    (reader as any)._publication = opening;
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(opening) };
    (FlutterEpubNavigator.create as jest.Mock).mockImplementation(
      async (_c: any, _p: any, _i: any, _prefs: any, setNav: any) => setNav({ destroy: jest.fn() })
    );

    await reader.openPublication("https://example.test/book/manifest.json", "urn:test:book", undefined, "{}", "[]");

    expect(audioNav.stop).toHaveBeenCalledTimes(1);
    expect(audioNav.destroy).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNav).toBeUndefined();
    expect((reader as any)._syncItems).toEqual([]);
  });

  it("discards a navigator built for another book instead of replaying it", async () => {
    // The audio-first flow's remaining hole: A narrates with no view, getPublication(B)
    // advances _publication, and audioEnable arrives before B's view mounts and runs
    // openPublication's teardown. The reuse branch must not play A "as" B.
    const reader = new ReadiumReader();
    const narrating = guidedNavPublication();
    const opening = guidedNavPublication();
    const staleNav = fakeAudioNav();
    const builtNav = fakeAudioNav();
    (reader as any)._publication = opening;
    (reader as any)._audioNav = staleNav;
    (reader as any)._audioNavPublication = narrating;
    (reader as any)._hasGuidedNavigation = true;
    (reader as any)._syncItems = [{ audio: "a.mp3", text: "chapter1.xhtml#p1" }];
    (initializeGuidedNavigationNavigator as jest.Mock).mockImplementation(
      async (_pub, _loc, _prefs, setNav) => setNav(builtNav, [])
    );

    await reader.audioEnable('{"speed":1.0}', undefined);

    expect(staleNav.stop).toHaveBeenCalledTimes(1);
    expect(staleNav.destroy).toHaveBeenCalledTimes(1);
    expect(initializeGuidedNavigationNavigator).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNav).toBe(builtNav);
    expect((reader as any)._audioNavPublication).toBe(opening);
    expect((reader as any)._syncItems).toEqual([]);
  });

  it("keeps the audioEnable preferences when the view re-opens the narrating audiobook", async () => {
    // The keep path must not record the view's initial preferences as active: a later
    // recovery restart rebuilds from them and would silently drop speed & friends.
    const reader = new ReadiumReader();
    const publication = audiobookPublication();
    (reader as any)._publication = publication;
    (reader as any)._audioNav = fakeAudioNav();
    (reader as any)._audioNavPublication = publication;
    (reader as any)._activeAudioPreferencesJson = '{"speed":2.0}';
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(publication) };

    await reader.openPublication(
      "https://example.test/audiobook/manifest.json", "urn:test:audiobook", undefined, '{"speed":1.0}', "[]"
    );

    expect((reader as any)._activeAudioPreferencesJson).toBe('{"speed":2.0}');
  });

  it("does not build a second audio navigator when the same audiobook is re-opened", async () => {
    const reader = new ReadiumReader();
    const publication = audiobookPublication();
    const audioNav = fakeAudioNav();
    (reader as any)._publication = publication;
    (reader as any)._audioNav = audioNav;
    (reader as any)._audioNavPublication = publication;
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(publication) };

    await reader.openPublication(
      "https://example.test/audiobook/manifest.json", "urn:test:audiobook", undefined, "{}", "[]"
    );

    expect(FlutterAudioNavigator.create).not.toHaveBeenCalled();
    expect(audioNav.stop).not.toHaveBeenCalled();
    expect((reader as any)._audioNav).toBe(audioNav);
  });

  it("still builds the audio navigator when an audiobook is opened for the first time", async () => {
    const reader = new ReadiumReader();
    const publication = audiobookPublication();
    (reader as any)._pubManager = { getOrFetch: jest.fn().mockResolvedValue(publication) };
    (FlutterAudioNavigator.create as jest.Mock).mockImplementation(
      async (_p: any, _i: any, _prefs: any, setNav: any) => setNav(fakeAudioNav())
    );

    await reader.openPublication(
      "https://example.test/audiobook/manifest.json", "urn:test:audiobook", undefined, "{}", "[]"
    );

    expect(FlutterAudioNavigator.create).toHaveBeenCalledTimes(1);
    expect((reader as any)._audioNavPublication).toBe(publication);
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

  it("rejects audioEnable with NoPublication before the publication is loaded", async () => {
    const reader = new ReadiumReader();
    const error = jest.spyOn(console, "error").mockImplementation(() => {});
    const emitError = jest.fn();
    (reader as any)._bridge.emitError = emitError;

    await expect(reader.audioEnable('{"speed":1.0}', undefined)).rejects.toMatchObject({
      code: ReadiumWebErrorCode.noPublication,
    });

    expect(initializeGuidedNavigationNavigator).not.toHaveBeenCalled();
    expect((reader as any)._audioNav).toBeUndefined();
    expect(error).toHaveBeenCalled();
    expect(emitError).not.toHaveBeenCalled();
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
