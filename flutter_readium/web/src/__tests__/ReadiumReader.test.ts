/**
 * Regression tests for ReadiumReader.closePublication teardown.
 *
 * closePublication must stop AND destroy every navigator and clear its
 * references. The audio navigator in particular must be *stopped* before it is
 * destroyed: an autoplay-blocked play() keeps retrying and the position poll
 * keeps emitting textLocators, so a navigator that is destroyed but not stopped
 * can leak stale locators into the next opened publication (observed via the
 * singleton reader's broadcast stream during web integration tests).
 */
import { Link, Links, Locator, LocatorLocations } from "@readium/shared";
import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;

/** Runs `fn` with minimal `window`/`document` globals, restoring them after. */
function withDomGlobals(fn: () => void): void {
  const savedWindow = (globalThis as any).window;
  const savedDocument = (globalThis as any).document;
  (globalThis as any).window = { updateReaderStatus: jest.fn() };
  (globalThis as any).document = { getElementById: () => null };
  try {
    fn();
  } finally {
    if (savedWindow === undefined) delete (globalThis as any).window;
    else (globalThis as any).window = savedWindow;
    if (savedDocument === undefined) delete (globalThis as any).document;
    else (globalThis as any).document = savedDocument;
  }
}

describe("closePublication teardown", () => {
  it("stops then destroys the audio navigator and tears down nav + TTS", () => {
    withDomGlobals(() => {
      const reader = new ReadiumReader();
      const audioNav = { stop: jest.fn(), destroy: jest.fn() };
      const ttsEngine = { destroy: jest.fn() };
      const nav = { destroy: jest.fn() };
      (reader as any)._audioNav = audioNav;
      (reader as any)._ttsEngine = ttsEngine;
      (reader as any)._nav = nav;

      reader.closePublication();

      // Audio: stopped AND destroyed, and stop must happen first so the
      // poll/retry loop is halted before teardown.
      expect(audioNav.stop).toHaveBeenCalledTimes(1);
      expect(audioNav.destroy).toHaveBeenCalledTimes(1);
      expect(audioNav.stop.mock.invocationCallOrder[0]).toBeLessThan(
        audioNav.destroy.mock.invocationCallOrder[0]
      );

      // TTS and visual navigator destroyed.
      expect(ttsEngine.destroy).toHaveBeenCalled();
      expect(nav.destroy).toHaveBeenCalled();

      // References cleared so nothing can keep emitting after close.
      expect((reader as any)._audioNav).toBeUndefined();
      expect((reader as any)._ttsEngine).toBeUndefined();
      expect((reader as any)._nav).toBeUndefined();
    });
  });

  it("does not throw when no navigators are active", () => {
    withDomGlobals(() => {
      const reader = new ReadiumReader();
      expect(() => reader.closePublication()).not.toThrow();
    });
  });
});

describe("audio stop lifecycle", () => {
  it("destroys TTS so clients must re-enable it", () => {
    withDomGlobals(() => {
      const reader = new ReadiumReader();
      const ttsEngine = { stop: jest.fn(), destroy: jest.fn() };
      (reader as any)._ttsEngine = ttsEngine;

      reader.stop();

      expect(ttsEngine.stop).toHaveBeenCalledTimes(1);
      expect(ttsEngine.destroy).toHaveBeenCalledTimes(1);
      expect(ttsEngine.stop.mock.invocationCallOrder[0]).toBeLessThan(
        ttsEngine.destroy.mock.invocationCallOrder[0]
      );
      expect((reader as any)._ttsEngine).toBeUndefined();
    });
  });

  describe("audioEnable lifecycle", () => {
    afterEach(() => {
      jest.restoreAllMocks();
    });

    it("recreates a plain audiobook navigator after destructive stop", async () => {
      const savedWindow = (globalThis as any).window;
      (globalThis as any).window = { updateTimebasedPlayerState: jest.fn() };
      const reader = new ReadiumReader();
      const locator = new Locator({
        href: "track.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=0"] }),
      });
      const stoppedAudioNav = {
        stop: jest.fn(),
        destroy: jest.fn(),
      };
      const audioNav = {
        currentLocator: locator,
        currentTime: 0,
        isPlaying: false,
        play: jest.fn(),
        pause: jest.fn(),
        go: jest.fn(async (_locator, _animated, cb) => cb(true)),
      };
      const create = jest
        .spyOn(FlutterAudioNavigator, "create")
        .mockImplementation(async (_publication, _initial, _prefs, setNav) => {
          setNav(audioNav as any);
        });

      (reader as any)._publication = { conformsToAudiobook: true };
      (reader as any)._audioNav = stoppedAudioNav;

      try {
        reader.stop();
        await reader.audioEnable("{}", undefined);

        expect(stoppedAudioNav.stop).toHaveBeenCalledTimes(1);
        expect(stoppedAudioNav.destroy).toHaveBeenCalledTimes(1);
        expect(create).toHaveBeenCalledTimes(1);
        expect(create.mock.calls[0][7]).toBeDefined();
        expect((reader as any)._audioNav).toBe(audioNav);
        expect(audioNav.play).toHaveBeenCalledTimes(1);
      } finally {
        if (savedWindow === undefined) delete (globalThis as any).window;
        else (globalThis as any).window = savedWindow;
      }
    });

    it("stores ToC audio locators after stop and restarts from them", async () => {
      const savedWindow = (globalThis as any).window;
      (globalThis as any).window = { updateTimebasedPlayerState: jest.fn() };
      const reader = new ReadiumReader();
      const stoppedLocator = new Locator({
        href: "track-01.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=4"] }),
      });
      const tocLocator = new Locator({
        href: "track-02.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=0"] }),
      });
      const audioNav = {
        currentLocator: tocLocator,
        currentTime: 0,
        isPlaying: false,
        play: jest.fn(),
        pause: jest.fn(),
        go: jest.fn(async (_locator, _animated, cb) => cb(true)),
      };
      const create = jest
        .spyOn(FlutterAudioNavigator, "create")
        .mockImplementation(async (_publication, initial, _prefs, setNav) => {
          expect(initial?.serialize()).toEqual(tocLocator.serialize());
          setNav(audioNav as any);
        });

      (reader as any)._publication = {
        conformsToAudiobook: true,
        readingOrder: { items: [{ href: "track-02.mp3", type: "audio/mpeg" }] },
        resources: { items: [] },
      };
      (reader as any)._audioNav = {
        currentLocator: stoppedLocator,
        stop: jest.fn(),
        destroy: jest.fn(),
      };

      try {
        reader.stop();
        await reader.goTo(JSON.stringify(tocLocator.serialize()));
        await reader.audioEnable("{}", undefined);

        expect(create).toHaveBeenCalledTimes(1);
        expect(create.mock.calls[0][7]).toBeDefined();
        expect((reader as any)._audioNav).toBe(audioNav);
        expect((reader as any)._stoppedAudioLocator).toBeUndefined();
        expect(audioNav.play).toHaveBeenCalledTimes(1);
      } finally {
        if (savedWindow === undefined) delete (globalThis as any).window;
        else (globalThis as any).window = savedWindow;
      }
    });

    it("manual retry after terminal failure reuses active audio preferences", () => {
      const reader = new ReadiumReader();
      const locator = new Locator({
        href: "track.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=9"] }),
      });
      const audioNav = {
        currentLocator: locator,
        play: jest.fn(),
      };
      const rebuiltNav = {
        currentLocator: locator,
        play: jest.fn(),
      };
      const recreate = jest
        .spyOn(FlutterAudioNavigator, "recreateAfterFailure")
        .mockImplementation((_initial, _prefs, setNav) => {
          setNav(rebuiltNav as any);
          return true;
        });
      jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(true);
      const retryAfterFailure = jest
        .spyOn(FlutterAudioNavigator, "retryAfterFailure")
        .mockImplementation(() => {});

      const publication = { conformsToAudiobook: true };
      (reader as any)._publication = publication;
      (reader as any)._audioNav = audioNav;
      // Every production assignment site stamps the navigator's publication;
      // the retry rebuild is keyed on that identity.
      (reader as any)._audioNavPublication = publication;
      (reader as any)._activeAudioPreferencesJson = '{"volume":0.5}';

      reader.play();

      expect(retryAfterFailure).toHaveBeenCalledTimes(1);
      expect(recreate).toHaveBeenCalledTimes(1);
      expect(recreate.mock.calls[0][0]).toBe(locator);
      expect(recreate.mock.calls[0][1]).toBe('{"volume":0.5}');
      expect((reader as any)._audioNav).toBe(rebuiltNav);
      expect(rebuiltNav.play).toHaveBeenCalledTimes(1);
    });

    it("manual retry after terminal failure maps a Media Overlay text locator to audio", () => {
      const reader = new ReadiumReader();
      const audioLocator = new Locator({
        href: "chap.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=1"] }),
      });
      const audioNav = { currentLocator: audioLocator, play: jest.fn() };
      const rebuiltNav = { currentLocator: audioLocator, play: jest.fn() };
      const recreate = jest
        .spyOn(FlutterAudioNavigator, "recreateAfterFailure")
        .mockImplementation((_initial, _prefs, setNav) => {
          setNav(rebuiltNav as any);
          return true;
        });
      jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(true);
      jest.spyOn(FlutterAudioNavigator, "retryAfterFailure").mockImplementation(() => {});

      const publication = {readingOrder: new Links([])};
      (reader as any)._publication = publication;
      (reader as any)._audioNav = audioNav;
      (reader as any)._audioNavPublication = publication;
      (reader as any)._syncItems = [
        { audioHref: "chap.mp3", audioStart: 12, audioEnd: 15, textHref: "chap.xhtml", textId: "p2" },
      ];

      const textLocator = new Locator({
        href: "chap.xhtml",
        type: "application/xhtml+xml",
        locations: new LocatorLocations({ fragments: ["p2"] }),
      });
      reader.play(JSON.stringify(textLocator.serialize()));

      const resumed = recreate.mock.calls[0][0];
      expect(resumed.href).toBe("chap.mp3");
      expect(resumed.locations?.fragments).toEqual(["t=12"]);
      expect(rebuiltNav.play).toHaveBeenCalledTimes(1);
    });

    it("discards a terminal-failed navigator built for a previous publication instead of rebuilding", () => {
      const reader = new ReadiumReader();
      const locator = new Locator({
        href: "track.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=9"] }),
      });
      const audioNav = {
        currentLocator: locator,
        play: jest.fn(),
        stop: jest.fn(),
        destroy: jest.fn(),
      };
      const create = jest.spyOn(FlutterAudioNavigator, "create");
      jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(true);
      const retryAfterFailure = jest.spyOn(FlutterAudioNavigator, "retryAfterFailure");

      // Stacked state: the old book still narrates while _publication advanced to B.
      (reader as any)._publication = { conformsToAudiobook: false };
      (reader as any)._audioNav = audioNav;
      (reader as any)._audioNavPublication = { conformsToAudiobook: true };

      reader.play();

      // Rebuilding would launder A's navigator through B's identity — discard instead.
      expect(retryAfterFailure).not.toHaveBeenCalled();
      expect(create).not.toHaveBeenCalled();
      expect(audioNav.stop).toHaveBeenCalledTimes(1);
      expect(audioNav.destroy).toHaveBeenCalledTimes(1);
      expect((reader as any)._audioNav).toBeUndefined();
      expect((reader as any)._audioNavPublication).toBeUndefined();
    });
  });

  it("destroys Media Overlay audio so re-enable recreates a fresh navigator", () => {
    withDomGlobals(() => {
      const reader = new ReadiumReader();
      const audioNav = { stop: jest.fn(), destroy: jest.fn() };
      (reader as any)._audioNav = audioNav;
      (reader as any)._hasGuidedNavigation = true;
      (reader as any)._syncItems = [{ audioHref: "chap.mp3" }];
      (reader as any)._lastMediaOverlayLocatorKey = "image0002.jpg";

      reader.stop();

      expect(audioNav.stop).toHaveBeenCalledTimes(1);
      expect(audioNav.destroy).toHaveBeenCalledTimes(1);
      expect(audioNav.stop.mock.invocationCallOrder[0]).toBeLessThan(
        audioNav.destroy.mock.invocationCallOrder[0]
      );
      expect((reader as any)._audioNav).toBeUndefined();
      expect((reader as any)._syncItems).toEqual([]);
      expect((reader as any)._lastMediaOverlayLocatorKey).toBeNull();
    });
  });

  it("destroys plain audiobook audio so clients must re-enable it", () => {
    withDomGlobals(() => {
      const reader = new ReadiumReader();
      const locator = new Locator({
        href: "track.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=12"] }),
      });
      const audioNav = { currentLocator: locator, stop: jest.fn(), destroy: jest.fn() };
      (reader as any)._audioNav = audioNav;

      reader.stop();

      expect(audioNav.stop).toHaveBeenCalledTimes(1);
      expect(audioNav.destroy).toHaveBeenCalledTimes(1);
      expect(audioNav.stop.mock.invocationCallOrder[0]).toBeLessThan(
        audioNav.destroy.mock.invocationCallOrder[0]
      );
      expect((reader as any)._audioNav).toBeUndefined();
      expect((reader as any)._stoppedAudioLocator).toBe(locator);
    });
  });
});

describe("audiobook playback intent", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("tracks explicit play, pause, and resume independently from player state", () => {
    const reader = new ReadiumReader();
    const audioNav = {
      play: jest.fn(),
      pause: jest.fn(),
    };
    const setPlaybackIntent = jest
      .spyOn(FlutterAudioNavigator, "setPlaybackIntent")
      .mockImplementation(() => {});
    (reader as any)._audioNav = audioNav;

    reader.play();
    reader.pause();
    reader.resume();

    expect(setPlaybackIntent.mock.calls).toEqual([[true], [false], [true]]);
  });
});

describe("audioEnable restore sequencing", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("resolves only after the restore seek finishes", async () => {
    jest.spyOn(FlutterAudioNavigator, "setPlaybackIntent").mockImplementation(() => {});
    const reader = new ReadiumReader();
    const target = new Locator({
      href: "track-01.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=5.6"] }),
    });
    let releaseGo: (() => void) | undefined;
    const audioNav = {
      currentLocator: new Locator({
        href: "track-01.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({ fragments: ["t=0"] }),
      }),
      currentTime: 0,
      isPlaying: false,
      play: jest.fn(),
      pause: jest.fn(),
      go: jest.fn(
        (_locator: Locator, _animated: boolean, cb: (ok: boolean) => void) =>
          new Promise<void>((resolve) => {
            releaseGo = () => {
              cb(true);
              resolve();
            };
          })
      ),
    };
    const publication = { conformsToAudiobook: true };
    (reader as any)._publication = publication;
    (reader as any)._audioNav = audioNav;
    (reader as any)._audioNavPublication = publication;

    let settled = false;
    const enabling = reader
      .audioEnable("{}", JSON.stringify(target.serialize()))
      .then(() => {
        settled = true;
      });

    await Promise.resolve();
    await Promise.resolve();

    expect(audioNav.go).toHaveBeenCalledTimes(1);
    // Must still be pending. Dart calls play() right after audioEnable resolves,
    // and a play() that lands while upstream go() is still navigating is
    // swallowed, so position polling never restarts and the player looks frozen.
    expect(settled).toBe(false);
    expect(audioNav.play).not.toHaveBeenCalled();

    releaseGo!();
    await enabling;

    expect(settled).toBe(true);
    expect(audioNav.play).toHaveBeenCalledTimes(1);
  });
});


describe("active Sync Narration navigation", () => {
  const guidedNavigationLink = new Link({href: "guided.json", type: "application/guided-navigation+json"});

  function session(bothFormats = false) {
    const reader = new ReadiumReader();
    const publication = { readingOrder: new Links([new Link({href: "chap.xhtml", alternates: new Links([
      new Link({href: "overlay.json", type: "application/vnd.readium.narration+json"}),
    ])})]), allLinks: [new Link({href: "chap.mp3", type: "audio/mpeg"})],
      manifest: {links: new Links(bothFormats ? [guidedNavigationLink] : [])} };
    const currentLocator = new Locator({href: "chap.mp3", type: "audio/mpeg", locations: new LocatorLocations({fragments: ["t=12"]})});
    const nav = {currentLocator, currentTime: 12, isPlaying: true, go: jest.fn(), play: jest.fn()};
    const seek = jest.spyOn(reader as any, "_seekAudioAndResume").mockResolvedValue(undefined);
    Object.assign(reader as any, {_audioNav: nav, _audioNavPublication: publication,
      _publication: {readingOrder: new Links([])}, _hasSyncNarration: false, _hasGuidedNavigation: true,
      _syncItems: [{textHref: "chap.xhtml", textId: "p1", audioHref: "chap.mp3", audioStart: 0, audioEnd: 5, tocHref: "chap.xhtml#section"},
        {textHref: "chap.xhtml", textId: "p2", audioHref: "chap.mp3", audioStart: 10, audioEnd: 15, tocHref: "chap.xhtml#section"}],
      _stoppedAudioLocator: currentLocator,
    });
    return {reader, nav, seek, currentLocator};
  }
  const target = (id: string) => JSON.stringify(new Locator({href: "chap.xhtml", type: "text/html", locations: new LocatorLocations({fragments: [id]})}).serialize());
  afterEach(() => jest.restoreAllMocks());
  it("unknown same-file anchor preserves navigator/cache and play resumes existing position", async () => {
    const {reader, nav, seek, currentLocator} = session();
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    await reader.goTo(target("unknown"));
    expect(seek).not.toHaveBeenCalled();
    expect(nav.go).not.toHaveBeenCalled();
    expect(nav.currentLocator).toBe(currentLocator);
    expect((reader as any)._stoppedAudioLocator).toBe(currentLocator);
    reader.play();
    expect(nav.play).toHaveBeenCalledTimes(1);
    expect(seek).not.toHaveBeenCalled();
  });
  it("same-file structural goTo and explicit play follow installed format despite new flags", async () => {
    const {reader, seek} = session();
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    await reader.goTo(target("section"));
    expect((seek.mock.calls[0][0] as Locator).locations.fragments).toEqual(["t=0"]);
    reader.play(target("section"));
    expect((seek.mock.calls[1][0] as Locator).href).toBe("chap.mp3");
    expect((seek.mock.calls[1][0] as Locator).locations.fragments).toEqual(["t=0"]);
  });
  it.each([true, false])("unmapped explicit Sync requests leave playback unchanged (playing=%s)", async playing => {
    const {reader, nav, seek, currentLocator} = session();
    nav.isPlaying = playing;
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    reader.play(target("t=30"));
    expect(seek).not.toHaveBeenCalled();
    expect(nav.play).not.toHaveBeenCalled();
    expect(nav.currentLocator).toBe(currentLocator);
    expect(nav.isPlaying).toBe(playing);
    Object.assign(reader as any, {_publication: (reader as any)._audioNavPublication,
      _hasSyncNarration: true, _hasGuidedNavigation: false});
    await reader.audioEnable("{}", target("t=30"));
    expect(seek).not.toHaveBeenCalled();
    expect(nav.play).not.toHaveBeenCalled();
    expect(nav.currentLocator).toBe(currentLocator);
    expect(nav.isPlaying).toBe(playing);
  });
  it("unknown target in the starting resource at a boundary cannot enable fallback", async () => {
    const {reader, nav, seek} = session();
    nav.currentLocator = new Locator({href: "chap.mp3", type: "audio/mpeg", locations: new LocatorLocations({fragments: ["t=16"]})});
    nav.currentTime = 16;
    (reader as any)._syncItems = [
      {textHref: "one.xhtml", textId: "boundary", audioHref: "chap.mp3", audioStart: 14, audioEnd: 16},
      {textHref: "two.xhtml", textId: "heading", audioHref: "chap.mp3", audioStart: 16, audioEnd: 18},
    ];
    const locator = new Locator({href: "two.xhtml", type: "text/html", locations: new LocatorLocations({fragments: ["unknown"]})});
    await reader.goTo(JSON.stringify(locator.serialize()));
    expect(seek).not.toHaveBeenCalled();
  });
  it("resolves uncued play once and does not recurse for an unknown anchor", async () => {
    const {reader, seek} = session();
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    const unknown = Locator.deserialize(JSON.parse(target("unknown")))!;
    const resolver = {isUncued: jest.fn(() => true), anchor: jest.fn(async () => unknown)};
    (reader as any)._uncuedTocTargets = resolver;
    reader.play(target("unknown"));
    await Promise.resolve();
    await Promise.resolve();
    expect(resolver.anchor).toHaveBeenCalledTimes(1);
    expect(seek).not.toHaveBeenCalled();
  });
  it("resolves an uncued target for goTo, play, and a reused audioEnable", async () => {
    const {reader, seek} = session();
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    const anchored = Locator.deserialize(JSON.parse(target("p2")))!;
    const resolver = {isUncued: (locator: Locator) => !locator.locations.fragments?.some((f) => f.startsWith("t=")), anchor: jest.fn(async () => anchored)};
    (reader as any)._uncuedTocTargets = resolver;
    await reader.goTo(target("empty-heading"));
    reader.play(target("empty-heading"));
    await Promise.resolve();
    Object.assign(reader as any, {_publication: (reader as any)._audioNavPublication,
      _hasSyncNarration: true, _hasGuidedNavigation: false});
    await reader.audioEnable("{}", target("empty-heading"));
    expect(resolver.anchor).toHaveBeenCalledTimes(3);
    expect(seek).toHaveBeenCalledTimes(3);
    for (const call of seek.mock.calls) {
      expect((call[0] as Locator).locations.fragments).toEqual(["t=10"]);
    }
  });
  it("resolves an uncued target before recreating a terminally failed session", async () => {
    const {reader, seek} = session();
    (reader as any)._publication = (reader as any)._audioNavPublication;
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(true);
    jest.spyOn(FlutterAudioNavigator, "retryAfterFailure").mockImplementation(() => {});
    const recreate = jest.spyOn(FlutterAudioNavigator, "recreateAfterFailure").mockReturnValue(true);
    const anchored = Locator.deserialize(JSON.parse(target("p2")))!;
    const resolver = {isUncued: (locator: Locator) => !locator.locations.fragments?.some((f) => f.startsWith("t=")),
      anchor: jest.fn(async () => anchored)};
    (reader as any)._uncuedTocTargets = resolver;
    reader.play(target("empty-heading"));
    await Promise.resolve();
    await Promise.resolve();
    expect(resolver.anchor).toHaveBeenCalledTimes(1);
    expect(recreate).toHaveBeenCalledTimes(1);
    expect(recreate.mock.calls[0][0]?.locations.fragments).toEqual(["t=10"]);
    expect(seek).not.toHaveBeenCalled();
  });
  it("discards an uncued play resolved after its session has been replaced", async () => {
    const {reader, seek} = session();
    jest.spyOn(FlutterAudioNavigator, "isTerminallyFailed").mockReturnValue(false);
    let resolve!: (locator: Locator) => void;
    (reader as any)._uncuedTocTargets = {isUncued: () => true,
      anchor: () => new Promise<Locator>((done) => {resolve = done;})};
    reader.play(target("empty-heading"));
    (reader as any)._uncuedTocTargets = undefined;
    resolve(Locator.deserialize(JSON.parse(target("p2")))!);
    await Promise.resolve();
    expect(seek).not.toHaveBeenCalled();
  });
  it("both formats retain Guided priority for active goTo", async () => {
    const {reader, seek} = session(true);
    await reader.goTo(target("section"));
    expect(seek).not.toHaveBeenCalled();
  });
});
