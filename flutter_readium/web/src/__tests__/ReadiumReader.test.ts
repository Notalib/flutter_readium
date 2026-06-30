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
import { Locator, LocatorLocations } from "@readium/shared";
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
        expect((reader as any)._audioNav).toBe(audioNav);
        expect((reader as any)._stoppedAudioLocator).toBeUndefined();
        expect(audioNav.play).toHaveBeenCalledTimes(1);
      } finally {
        if (savedWindow === undefined) delete (globalThis as any).window;
        else (globalThis as any).window = savedWindow;
      }
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
