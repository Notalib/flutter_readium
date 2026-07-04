/**
 * Web counterpart of iOS's `AudioStreamErrorPolicy.swift` / Android's
 * `AudioStreamErrorPolicy.kt`. Classifies an audio streaming failure and
 * defines the exponential backoff used to recover from it.
 *
 * Browser constraint: `HTMLMediaElement` only ever exposes a `MediaError`
 * with one of 4 generic codes — there is no HTTP status on it, so unlike
 * iOS/Android, web CANNOT distinguish 401/403 (`AudioStreamAuthError`) or
 * other 4xx (`AudioStreamHTTPError`) from a generic network failure. Do not
 * fake that distinction; `AudioStreamNetworkError` is the closest honest
 * mapping for "the browser gave up on the network fetch".
 */

import { ReadiumErrorEventData } from "../bridge/ReadiumBridge";

/** What the audio navigator should do about a playback failure. */
export type AudioStreamErrorAction =
  | { kind: "ignore" }
  | { kind: "retry" }
  | { kind: "fail"; code: string; httpStatus?: number };

export const AudioStreamErrorAction = {
  ignore: (): AudioStreamErrorAction => ({ kind: "ignore" }),
  retry: (): AudioStreamErrorAction => ({ kind: "retry" }),
  fail: (code: string, httpStatus?: number): AudioStreamErrorAction => ({
    kind: "fail",
    code,
    ...(httpStatus !== undefined ? { httpStatus } : {}),
  }),
};

/**
 * Duck-typed view of the standard `MediaError` interface — declared locally
 * (rather than relying on the DOM lib) so the classifier is a plain function
 * that unit tests can call under `testEnvironment: "node"`, with no browser
 * globals required.
 */
export interface MediaErrorLike {
  readonly code: number;
}

// MediaError.code constants (see MDN): the real values, duplicated here so
// this module has no dependency on the DOM lib being loaded. Exported so
// callers (e.g. the HTTP probe wiring in FlutterAudioNavigator) can recognize
// the codes that are already conclusive from MediaError alone, without
// re-declaring the magic numbers.
export const MEDIA_ERR_ABORTED = 1;
export const MEDIA_ERR_NETWORK = 2;
export const MEDIA_ERR_DECODE = 3;
export const MEDIA_ERR_SRC_NOT_SUPPORTED = 4;

/**
 * Classifies an error surfaced by the ts-toolkit `AudioNavigator`'s `error`
 * listener. That listener forwards `HTMLMediaElement.error` (a `MediaError`)
 * for engine-level playback failures, but can also forward an arbitrary
 * exception thrown by the underlying `play()` call (e.g. a rejected
 * autoplay promise) — such values have no numeric `code` and are treated as
 * a non-network terminal failure, matching iOS/Android's default-terminal
 * fallback for unclassifiable errors.
 *
 * Mapping (browser-only classes available — no HTTP status):
 *   MEDIA_ERR_ABORTED            -> ignore   (e.g. cancelled during teardown/seek)
 *   MEDIA_ERR_NETWORK            -> retry
 *   MEDIA_ERR_DECODE             -> fail(AudioStreamError)
 *   MEDIA_ERR_SRC_NOT_SUPPORTED  -> fail(AudioStreamNetworkError)
 *   anything else / no code      -> fail(AudioStreamError)
 */
export function classifyAudioStreamError(error: unknown): AudioStreamErrorAction {
  const code = (error as MediaErrorLike | null | undefined)?.code;

  switch (code) {
    case MEDIA_ERR_ABORTED:
      return AudioStreamErrorAction.ignore();
    case MEDIA_ERR_NETWORK:
      return AudioStreamErrorAction.retry();
    case MEDIA_ERR_DECODE:
      return AudioStreamErrorAction.fail("AudioStreamError");
    case MEDIA_ERR_SRC_NOT_SUPPORTED:
      return AudioStreamErrorAction.fail("AudioStreamNetworkError");
    default:
      return AudioStreamErrorAction.fail("AudioStreamError");
  }
}

/**
 * Exponential backoff policy for audio stream recovery: 1s, 2s, 4s.
 * Mirrors iOS's `AudioRecoveryPolicy` / Android's `AudioRecoveryPolicy`.
 */
export class AudioRecoveryPolicy {
  constructor(public readonly maxAttempts: number = 3) {}

  delayMillis(forAttempt: number): number {
    const attempt = Math.max(forAttempt, 1) - 1;
    return 1000 * Math.pow(2, attempt);
  }
}

/**
 * Callbacks the recovery controller drives. Kept narrow and injected (rather
 * than depending on `AudioNavigator`/DOM directly) so the bounded-retry /
 * suppression / latch state machine is unit-testable without a live media
 * element. `FlutterAudioNavigator` wires these to the real navigator.
 */
export interface AudioRecoveryHooks {
  /** Emit a bridge error event (message, code, optional structured data). */
  emitError(message: string, code: string, data?: ReadiumErrorEventData): void;
  /** Pin the timebased state to "loading" (or, on terminal failure, "failure"). */
  setPinnedState(state: "loading" | "failure"): void;
  /**
   * Rebuild playback at `href` and resolve `true` once playback position has
   * actually advanced within the policy's verification window — `false` on
   * timeout or a rebuild failure. Mirrors iOS/Android's `playbackAdvanced`
   * check: being in a "ready"/"playing" state alone is not a reliable signal.
   */
  rebuildAndVerify(href: string): Promise<boolean>;
  /** Stop playback as part of entering the terminal failure state. */
  stopPlayback(): void;
  /** sleep(ms) — injected so tests can fake it instead of waiting in real time. */
  delay(ms: number): Promise<void>;
}

/**
 * Bounded exponential-backoff recovery loop for a retryable audio streaming
 * failure, plus the terminal-failure latch. Mirrors iOS's
 * `FlutterAudioNavigator._recoveryTask` / Android's `startRecovery` +
 * `isTerminallyFailed`.
 *
 * - While recovering, `isSuppressed()` is true: callers should drop the
 *   underlying navigator's own state emissions (Buffering/Ready/stalled
 *   churn) and let only the pinned "loading" state (emitted per attempt)
 *   reach the bridge.
 * - Once terminally failed, `isTerminallyFailed()` latches `true` until
 *   `clearFailure()` is called (from `play()` after a failure) — further
 *   errors from the (already torn down) navigator are ignored.
 */
export class AudioStreamRecoveryController {
  private recovering = false;
  private terminallyFailed = false;

  constructor(
    private readonly hooks: AudioRecoveryHooks,
    private readonly policy: AudioRecoveryPolicy = new AudioRecoveryPolicy()
  ) {}

  isSuppressed(): boolean {
    return this.recovering;
  }

  isTerminallyFailed(): boolean {
    return this.terminallyFailed;
  }

  /** Clears the terminal-failure latch. Call before retrying playback (e.g. from `play()`). */
  clearFailure(): void {
    this.terminallyFailed = false;
  }

  /**
   * Handles an error already classified by {@link classifyAudioStreamError}.
   * No-ops for `ignore`, latches+emits for `fail`, and starts (or ignores, if
   * already running) the recovery loop for `retry`.
   *
   * @param message      Human-readable error description for the bridge event.
   * @param action       Result of `classifyAudioStreamError(error)`.
   * @param resumeHref   href to rebuild/retry at (last known locator).
   */
  handle(message: string, action: AudioStreamErrorAction, resumeHref: string): void {
    // Latched terminal failure: further errors from the (already torn down)
    // navigator are noise until play() retries.
    if (this.terminallyFailed) return;

    switch (action.kind) {
      case "ignore":
        return;
      case "fail":
        this.enterTerminalFailure(message, action.code, resumeHref, action.httpStatus);
        return;
      case "retry":
        if (this.recovering) return; // recovery already in progress
        void this.startRecovery(message, resumeHref);
        return;
    }
  }

  private async startRecovery(message: string, href: string): Promise<void> {
    this.recovering = true;
    try {
      for (let attempt = 1; attempt <= this.policy.maxAttempts; attempt++) {
        this.hooks.emitError(message, "AudioStreamRetry", {
          href,
          attempt,
          maxAttempts: this.policy.maxAttempts,
        });
        this.hooks.setPinnedState("loading");

        await this.hooks.delay(this.policy.delayMillis(attempt));

        const recovered = await this.hooks.rebuildAndVerify(href);
        if (recovered) return; // regular state emissions resume
      }
      this.enterTerminalFailure(message, "AudioStreamFailed", href);
    } finally {
      this.recovering = false;
    }
  }

  /**
   * Terminal failure: stop playback, emit the terminal error event + "failure"
   * state once, then latch. The latch is an explicit flag (not inferred from
   * the last emitted state) so state churn from a torn-down navigator can't
   * un-latch it.
   */
  private enterTerminalFailure(
    message: string,
    code: string,
    href?: string,
    httpStatus?: number
  ): void {
    if (this.terminallyFailed) return;
    this.terminallyFailed = true;

    this.hooks.stopPlayback();
    this.hooks.emitError(
      message,
      code,
      href !== undefined || httpStatus !== undefined ? { href, httpStatus } : undefined
    );
    this.hooks.setPinnedState("failure");
  }
}
