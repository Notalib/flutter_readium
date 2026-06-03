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
