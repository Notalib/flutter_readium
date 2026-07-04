/**
 * Unit tests for the web audio-streaming error classifier and backoff policy.
 * Mirrors the iOS (`AudioStreamErrorPolicy.swift`) and Android
 * (`AudioStreamErrorPolicyTest.kt`) test cases where the browser's
 * `MediaError` surface allows an equivalent case.
 */

import {
  AudioRecoveryHooks,
  AudioRecoveryPolicy,
  AudioStreamErrorAction,
  AudioStreamRecoveryController,
  classifyAudioStreamError,
  MediaErrorLike,
} from "../navigators/AudioStreamErrorPolicy";

function mediaError(code: number): MediaErrorLike {
  return { code };
}

describe("classifyAudioStreamError", () => {
  it("MEDIA_ERR_ABORTED (1) is ignored", () => {
    expect(classifyAudioStreamError(mediaError(1))).toEqual(AudioStreamErrorAction.ignore());
  });

  it("MEDIA_ERR_NETWORK (2) is retryable", () => {
    expect(classifyAudioStreamError(mediaError(2))).toEqual(AudioStreamErrorAction.retry());
  });

  it("MEDIA_ERR_DECODE (3) is a terminal AudioStreamError", () => {
    expect(classifyAudioStreamError(mediaError(3))).toEqual(
      AudioStreamErrorAction.fail("AudioStreamError")
    );
  });

  it("MEDIA_ERR_SRC_NOT_SUPPORTED (4) is a terminal AudioStreamNetworkError", () => {
    expect(classifyAudioStreamError(mediaError(4))).toEqual(
      AudioStreamErrorAction.fail("AudioStreamNetworkError")
    );
  });

  it("an unknown numeric code is a terminal AudioStreamError (unclassifiable, matches iOS/Android default-terminal fallback)", () => {
    expect(classifyAudioStreamError(mediaError(99))).toEqual(
      AudioStreamErrorAction.fail("AudioStreamError")
    );
  });

  it("a value with no code (e.g. a rejected play() promise) is a terminal AudioStreamError", () => {
    expect(classifyAudioStreamError(new Error("NotAllowedError"))).toEqual(
      AudioStreamErrorAction.fail("AudioStreamError")
    );
  });

  it("null/undefined is a terminal AudioStreamError", () => {
    expect(classifyAudioStreamError(null)).toEqual(AudioStreamErrorAction.fail("AudioStreamError"));
    expect(classifyAudioStreamError(undefined)).toEqual(
      AudioStreamErrorAction.fail("AudioStreamError")
    );
  });
});

describe("AudioRecoveryPolicy", () => {
  it("defaults to 3 max attempts", () => {
    expect(new AudioRecoveryPolicy().maxAttempts).toBe(3);
  });

  it("backs off 1s, 2s, 4s", () => {
    const policy = new AudioRecoveryPolicy();
    expect(policy.delayMillis(1)).toBe(1000);
    expect(policy.delayMillis(2)).toBe(2000);
    expect(policy.delayMillis(3)).toBe(4000);
  });

  it("treats attempt 0 or negative the same as attempt 1", () => {
    const policy = new AudioRecoveryPolicy();
    expect(policy.delayMillis(0)).toBe(1000);
    expect(policy.delayMillis(-5)).toBe(1000);
  });

  it("honors a custom maxAttempts", () => {
    const policy = new AudioRecoveryPolicy(5);
    expect(policy.maxAttempts).toBe(5);
  });

  it("defaults stallTimeoutSeconds to 20", () => {
    expect(new AudioRecoveryPolicy().stallTimeoutSeconds).toBe(20.0);
  });

  it("honors a custom backoffBaseSeconds", () => {
    const policy = new AudioRecoveryPolicy(3, 2.0);
    expect(policy.delayMillis(1)).toBe(2000);
    expect(policy.delayMillis(2)).toBe(4000);
    expect(policy.delayMillis(3)).toBe(8000);
  });

  it("fromJson parses all fields", () => {
    const policy = AudioRecoveryPolicy.fromJson({
      maxAttempts: 5,
      backoffBaseSeconds: 2.0,
      stallTimeoutSeconds: 30.0,
    });
    expect(policy.maxAttempts).toBe(5);
    expect(policy.backoffBaseSeconds).toBe(2.0);
    expect(policy.stallTimeoutSeconds).toBe(30.0);
  });

  it("fromJson falls back to defaults for missing/null input", () => {
    expect(AudioRecoveryPolicy.fromJson(undefined)).toEqual(new AudioRecoveryPolicy());
    expect(AudioRecoveryPolicy.fromJson(null)).toEqual(new AudioRecoveryPolicy());
    expect(AudioRecoveryPolicy.fromJson({})).toEqual(new AudioRecoveryPolicy());
  });
});

// ---------------------------------------------------------------------------
// AudioStreamRecoveryController
// ---------------------------------------------------------------------------

/**
 * Records hook invocations and lets the test script rebuildAndVerify outcomes.
 * `delay` resolves immediately (no fake timers needed) so recovery loops run
 * to completion synchronously from the test's perspective (still async/await).
 */
function fakeHooks(rebuildResults: boolean[]): AudioRecoveryHooks & { calls: string[] } {
  const calls: string[] = [];
  let rebuildCallIndex = 0;
  return {
    calls,
    emitError(message, code, data) {
      calls.push(`emitError(${code}${data ? `, ${JSON.stringify(data)}` : ""})`);
    },
    setPinnedState(state) {
      calls.push(`setPinnedState(${state})`);
    },
    async rebuildAndVerify(href) {
      calls.push(`rebuildAndVerify(${href})`);
      const result = rebuildResults[rebuildCallIndex] ?? false;
      rebuildCallIndex++;
      return result;
    },
    stopPlayback() {
      calls.push("stopPlayback()");
    },
    async delay(ms) {
      calls.push(`delay(${ms})`);
    },
  };
}

describe("AudioStreamRecoveryController", () => {
  it("ignore: does nothing", () => {
    const hooks = fakeHooks([]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.ignore(), "chap1.mp3");
    expect(hooks.calls).toEqual([]);
    expect(controller.isTerminallyFailed()).toBe(false);
    expect(controller.isSuppressed()).toBe(false);
  });

  it("fail: stops playback, emits the terminal code, pins failure state, and latches", () => {
    const hooks = fakeHooks([]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.fail("AudioStreamError"), "chap1.mp3");
    expect(hooks.calls).toEqual([
      "stopPlayback()",
      `emitError(AudioStreamError, ${JSON.stringify({ href: "chap1.mp3" })})`,
      "setPinnedState(failure)",
    ]);
    expect(controller.isTerminallyFailed()).toBe(true);
  });

  it("fail: a second error after latching is ignored (no duplicate emission)", () => {
    const hooks = fakeHooks([]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.fail("AudioStreamError"), "chap1.mp3");
    hooks.calls.length = 0;
    controller.handle("err2", AudioStreamErrorAction.fail("AudioStreamNetworkError"), "chap1.mp3");
    expect(hooks.calls).toEqual([]);
  });

  it("fail: httpStatus on the action is included in the emitted data", () => {
    const hooks = fakeHooks([]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.fail("AudioStreamHTTPError", 404), "chap1.mp3");
    expect(hooks.calls).toEqual([
      "stopPlayback()",
      `emitError(AudioStreamHTTPError, ${JSON.stringify({ href: "chap1.mp3", httpStatus: 404 })})`,
      "setPinnedState(failure)",
    ]);
  });

  it("clearFailure un-latches so a subsequent error is handled again", () => {
    const hooks = fakeHooks([]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.fail("AudioStreamError"), "chap1.mp3");
    controller.clearFailure();
    expect(controller.isTerminallyFailed()).toBe(false);
    controller.handle("err", AudioStreamErrorAction.fail("AudioStreamError"), "chap1.mp3");
    expect(controller.isTerminallyFailed()).toBe(true);
  });

  it("retry: recovers on the first attempt — emits one AudioStreamRetry, pins loading, rebuilds, then stops", async () => {
    const hooks = fakeHooks([true]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    await flushMicrotasks();
    expect(hooks.calls).toEqual([
      `emitError(AudioStreamRetry, ${JSON.stringify({ href: "chap1.mp3", attempt: 1, maxAttempts: 3 })})`,
      "setPinnedState(loading)",
      "delay(1000)",
      "rebuildAndVerify(chap1.mp3)",
    ]);
    expect(controller.isTerminallyFailed()).toBe(false);
    expect(controller.isSuppressed()).toBe(false); // recovery finished
  });

  it("retry: exhausts all 3 attempts with 1s/2s/4s backoff, then enters terminal failure", async () => {
    const hooks = fakeHooks([false, false, false]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    await flushMicrotasks();
    expect(hooks.calls).toEqual([
      `emitError(AudioStreamRetry, ${JSON.stringify({ href: "chap1.mp3", attempt: 1, maxAttempts: 3 })})`,
      "setPinnedState(loading)",
      "delay(1000)",
      "rebuildAndVerify(chap1.mp3)",
      `emitError(AudioStreamRetry, ${JSON.stringify({ href: "chap1.mp3", attempt: 2, maxAttempts: 3 })})`,
      "setPinnedState(loading)",
      "delay(2000)",
      "rebuildAndVerify(chap1.mp3)",
      `emitError(AudioStreamRetry, ${JSON.stringify({ href: "chap1.mp3", attempt: 3, maxAttempts: 3 })})`,
      "setPinnedState(loading)",
      "delay(4000)",
      "rebuildAndVerify(chap1.mp3)",
      "stopPlayback()",
      `emitError(AudioStreamNetworkError, ${JSON.stringify({ href: "chap1.mp3" })})`,
      "setPinnedState(failure)",
    ]);
    expect(controller.isTerminallyFailed()).toBe(true);
  });

  it("retry: succeeding on the second attempt stops the loop early", async () => {
    const hooks = fakeHooks([false, true]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    await flushMicrotasks();
    expect(hooks.calls.filter((c) => c.startsWith("rebuildAndVerify"))).toHaveLength(2);
    expect(controller.isTerminallyFailed()).toBe(false);
  });

  it("retry: a second retryable error while recovering is ignored (no overlapping recovery loops)", async () => {
    const hooks = fakeHooks([true]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    // Recovery is in-flight (before the awaited delay/rebuild resolve).
    expect(controller.isSuppressed()).toBe(true);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    await flushMicrotasks();
    expect(hooks.calls.filter((c) => c.startsWith("emitError(AudioStreamRetry"))).toHaveLength(1);
  });

  it("isSuppressed() is true only while a recovery attempt is in flight", async () => {
    const hooks = fakeHooks([false, false, false]);
    const controller = new AudioStreamRecoveryController(hooks);
    controller.handle("err", AudioStreamErrorAction.retry(), "chap1.mp3");
    expect(controller.isSuppressed()).toBe(true);
    await flushMicrotasks();
    expect(controller.isSuppressed()).toBe(false);
  });
});

/** Flushes pending microtask queues so async recovery loops (awaited via
 * hooks that resolve immediately) run to completion before assertions. */
function flushMicrotasks(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
