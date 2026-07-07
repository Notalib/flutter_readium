import {
  AudioNavigator,
  AudioNavigatorConfiguration,
  AudioNavigatorListeners,
  IAudioPreferences,
} from "@readium/navigator";
import { Locator, LocatorLocations, Timeline } from "@readium/shared";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { ReadiumPublication, findLinkByHref } from "../utils/ReadiumExtensions";
import { audioPreferencesFromJson } from "../preferences/FlutterAudioPreferences";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import {
  AudioStreamErrorAction,
  AudioStreamRecoveryController,
  classifyAudioStreamError,
  getCurrentAudioRecoveryPolicy,
  MEDIA_ERR_ABORTED,
  MEDIA_ERR_DECODE,
  MediaErrorLike,
} from "./AudioStreamErrorPolicy";
import { probeAudioStreamHttpStatus } from "./AudioStreamHttpProbe";
import { ReadiumWebError, ReadiumWebErrorCode } from "../errors/ReadiumWebError";

const log = createLogger("AudioNav");

/** Poll interval while waiting for playback position to advance during recovery. */
const RECOVERY_VERIFY_POLL_MS = 250;
/** Minimum position advance (seconds) counted as "playback actually resumed". */
const RECOVERY_VERIFY_MIN_ADVANCE_S = 0.1;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class TimeoutError extends Error {}

function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  message: string
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new TimeoutError(message)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

/**
 * Builds a function that computes publication-wide `totalProgression` for an
 * audio locator using accumulated track durations from `readingOrder`.
 *
 * Requires every `readingOrder.items[].duration` to be present and > 0. If any
 * is missing, logs a single warning and returns a no-op that yields `undefined`
 * — consumers should then leave `totalProgression` off the emitted locator.
 *
 * The upstream `@readium/navigator` AudioNavigator never populates
 * `totalProgression` after construction (it sets `0` once and then drops the
 * field on every subsequent `copyWithLocations`), so we have to compute it
 * ourselves before emitting locators back to Dart.
 */
export function makeAudioTotalProgressionFn(
  publication: ReadiumPublication
): (locator: Locator) => number | undefined {
  const items = publication.readingOrder.items;
  const missing = items.some(
    (i) => i.duration === undefined || i.duration <= 0
  );
  if (missing) {
    log.warn(
      "Cannot compute audio totalProgression: one or more readingOrder items missing duration"
    );
    return () => undefined;
  }
  const cumulative: number[] = [];
  let total = 0;
  for (const item of items) {
    cumulative.push(total);
    total += item.duration!;
  }
  return (locator: Locator) => {
    if (total <= 0) return undefined;
    const bareHref = locator.href.split("#")[0];
    const idx = items.findIndex((i) => i.href === bareHref);
    if (idx < 0) return undefined;
    const time = locator.locations?.time?.() ?? 0;
    const value = (cumulative[idx] + time) / total;
    return Math.min(1, Math.max(0, value));
  };
}

/**
 * Returns a copy of `locator` with `totalProgression` set. No-op when the
 * computed value is `undefined` (e.g. durations missing from manifest).
 */
function withTotalProgression(
  locator: Locator,
  totalProgression: number | undefined
): Locator {
  if (totalProgression === undefined) return locator;
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    text: locator.text,
    locations: new LocatorLocations({
      fragments: locator.locations?.fragments,
      progression: locator.locations?.progression,
      position: locator.locations?.position,
      totalProgression,
      otherLocations: locator.locations?.otherLocations,
    }),
  });
}

/**
 * Returns a copy of `locator` with `tocHref` injected into
 * `locations.otherLocations`. Used by plain audiobook sessions to propagate the
 * current ToC chapter href so Dart-side `Locator.locations.tocHref` is populated.
 * No-op when `tocHref` is undefined.
 */
export function withTocHref(locator: Locator, tocHref: string | undefined): Locator {
  if (!tocHref) return locator;
  const merged = new Map<string, any>(locator.locations?.otherLocations ?? []);
  merged.set("tocHref", tocHref);
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    text: locator.text,
    locations: new LocatorLocations({
      fragments: locator.locations?.fragments,
      progression: locator.locations?.progression,
      position: locator.locations?.position,
      totalProgression: locator.locations?.totalProgression,
      otherLocations: merged,
    }),
  });
}

export function buildStatePayload(
  state: string,
  nav: AudioNavigator,
  locator?: Locator,
  totalProgressDuration?: number,
  totalDuration?: number
): string {
  const currentLocator = locator ?? nav.currentLocator;
  return JSON.stringify({
    state,
    currentOffset: Math.round(nav.currentTime * 1000),
    currentDuration: nav.duration > 0 ? Math.round(nav.duration * 1000) : null,
    totalProgressDuration: totalProgressDuration ?? null,
    totalDuration: totalDuration ?? null,
    // Use serialize() so otherLocations Map entries are inlined into locations.
    // Plain JSON.stringify drops Map entries silently.
    currentLocator: currentLocator?.serialize(),
  });
}

function makePublicationTotalDurationMs(
  publication: ReadiumPublication
): number | undefined {
  const items = publication.readingOrder.items;
  if (items.length === 0) return undefined;
  const missing = items.some((i) => i.duration === undefined || i.duration <= 0);
  if (missing) return undefined;
  const totalSeconds = items.reduce((sum, item) => sum + item.duration!, 0);
  if (totalSeconds <= 0) return undefined;
  return Math.round(totalSeconds * 1000);
}

function makeTotalProgressDurationMs(
  locator: Locator,
  publicationTotalDurationMs: number | undefined
): number | undefined {
  if (publicationTotalDurationMs === undefined) return undefined;
  const totalProgression = locator.locations?.totalProgression;
  if (totalProgression === undefined) return undefined;
  const clamped = Math.min(1, Math.max(0, totalProgression));
  return Math.round(clamped * publicationTotalDurationMs);
}


/**
 * Optional locator mapper for custom audio sessions (e.g. Media Overlay).
 *
 * When provided, every state-emitting listener passes the raw AudioNavigator
 * locator through this mapper before emitting.  The mapper returns:
 *   stateLocator — used as currentLocator in the timebased state payload.
 *   textLocator  — if present, also emitted to window.updateTextLocator.
 *
 * When absent, the raw locator is used directly (standard audiobook behaviour)
 * and updateTextLocator is only emitted on positionChanged events.
 */
export type AudioLocatorMapper = (
  nav: AudioNavigator,
  audioLocator: Locator
) => {
  stateLocator: Locator;
  /**
   * High-fidelity text locator for internal sync callbacks
   * (e.g. comic panel auto-pan on Guided Navigation cues).
   */
  textLocator?: Locator;
  /**
   * Coarse text locator for the public bridge event (`updateTextLocator`).
   * Falls back to `textLocator` when omitted.
   */
  publicTextLocator?: Locator;
};

/**
 * Narrow structural view of the parts of `AudioNavigator` that
 * {@link seekAudioAndResume} drives. Declaring exactly the members used (rather
 * than depending on the full `AudioNavigator`) keeps the helper decoupled and
 * trivially fakeable in unit tests. The real `AudioNavigator` satisfies this
 * interface structurally, so callers pass it directly.
 */
export interface SeekableAudioNavigator {
  readonly isPlaying: boolean;
  readonly currentLocator: Locator;
  readonly currentTime: number;
  play(): void;
  pause(): void;
  go(locator: Locator, animated: boolean, cb: (ok: boolean) => void): Promise<void>;
}

/**
 * Tolerance (seconds) for treating a requested seek target as "already there".
 * The upstream same-position hang (see {@link seekAudioAndResume}) only triggers
 * on an exact match, but `mediaElement.currentTime` can drift by a few
 * milliseconds from the value we requested, so a small window avoids issuing a
 * redundant — and hang-prone — seek while never skipping a real reposition.
 */
const SAME_POSITION_EPSILON_S = 0.1;

/**
 * True when `nav` is already positioned at `audioLocator` (same track href and a
 * current time within {@link SAME_POSITION_EPSILON_S}). Used to avoid a
 * redundant seek that would hang upstream `go()`.
 */
function isAlreadyAtPosition(
  nav: SeekableAudioNavigator,
  audioLocator: Locator
): boolean {
  const targetHref = audioLocator.href.split("#")[0];
  const currentHref = nav.currentLocator.href.split("#")[0];
  if (targetHref !== currentHref) return false;
  const targetTime = audioLocator.locations?.time();
  if (targetTime === undefined) return false;
  return Math.abs(targetTime - nav.currentTime) <= SAME_POSITION_EPSILON_S;
}

/**
 * Seeks `nav` to `audioLocator` and (optionally) resumes playback afterwards,
 * restarting upstream position polling.
 *
 * Works around an upstream `AudioNavigator` quirk: `go()` stops position polling
 * for the duration of the seek and, when it finishes, resumes playback via a
 * bare `play()`. The underlying audio engine's `play()` no-ops when the element
 * is already playing, so the DOM "play" event never re-fires and position
 * polling is never restarted. The result is a frozen `currentLocator` and Media
 * Overlay highlights that only advance on the next pause/seek (those fire
 * `positionChanged` directly).
 *
 * To force a clean restart we pause the engine first (when it is playing) so the
 * post-seek `play()` is a genuine paused→playing transition, which re-fires the
 * DOM "play" event and restarts polling.
 *
 * Additionally guards a second upstream hazard: `AudioNavigator.seek()` issues
 * `mediaElement.currentTime = currentTime` when the requested time equals the
 * current one, which fires no "seeked" event. `go()`'s `waitForLoadedAndSeeked`
 * then never resolves, leaving `_isNavigating` stuck `true` forever — every
 * subsequent DOM "play" is swallowed by its `if (_isNavigating) return` guard
 * and polling never restarts. This is exactly the fresh-init Media Overlay case:
 * the navigator is constructed already seeked to the start cue, then `play()`
 * seeks to that same cue. When we detect the target is already the current
 * position we skip `go()` entirely and just restart playback.
 *
 * @param nav           Active audio navigator.
 * @param audioLocator  Audio-domain locator to seek to (href + `t=` fragment).
 * @param resumePlaying When true, playback resumes once the seek completes.
 */
export function seekAudioAndResume(
  nav: SeekableAudioNavigator,
  audioLocator: Locator,
  resumePlaying: boolean
): Promise<void> {
  // Already at the target: a real seek would set currentTime to its current
  // value, fire no "seeked", and hang upstream go(). Restart playback directly
  // so the DOM "play" event re-fires and position polling resumes.
  if (isAlreadyAtPosition(nav, audioLocator)) {
    log.debug("seekAudioAndResume: already at target", audioLocator.href, audioLocator.locations?.fragments?.[0] ?? "");
    if (resumePlaying) {
      if (nav.isPlaying) nav.pause(); // force a paused→playing transition
      nav.play();
    }
    return Promise.resolve();
  }

  // Pausing here (when playing) guarantees the post-seek play() restarts the
  // upstream position poll; go() alone would leave it stopped.
  log.debug("seekAudioAndResume: seeking", audioLocator.href, audioLocator.locations?.fragments?.[0] ?? "", resumePlaying ? "and resuming" : "without resume");
  if (nav.isPlaying) nav.pause();
  return nav.go(audioLocator, false, (ok) => {
    if (!ok) {
      log.warn("seekAudioAndResume: audio seek failed for", audioLocator.href);
      return;
    }
    log.debug("seekAudioAndResume: seek completed", audioLocator.href);
    if (resumePlaying) nav.play();
  });
}

// When a publication is closed, the upstream AudioNavigator can still fire a
// trailing event (e.g. a settling `onSeeked` → `positionChanged`) after stop()
// and destroy(). Those would emit a stale textLocator / timebased state to Dart
// and run the visual Media Overlay sync against a torn-down frame ("Trying to use
// frame window when it doesn't exist"). `_emitState` is the single chokepoint for
// all such emissions, so gating it here suppresses any post-close stragglers.
// Re-enabled whenever a fresh AudioNavigator is created (see FlutterAudioNavigator.create).
let _emissionsEnabled = true;

/** Enable/disable audio navigator emissions (text/state/visual sync). */
export function setAudioEmissionsEnabled(enabled: boolean): void {
  log.debug(`Audio emissions ${enabled ? "enabled" : "disabled"}`);
  _emissionsEnabled = enabled;
}

function _emitState(
  state: string,
  nav: AudioNavigator,
  rawLocator: Locator | undefined,
  mapper: AudioLocatorMapper | undefined,
  alsoText: boolean,
  computeTotalProgression: (locator: Locator) => number | undefined,
  publicationTotalDurationMs: number | undefined,
  onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void,
  getTocHref?: () => string | undefined
): void {
  if (!_emissionsEnabled) {
    log.debug(
      "emitState suppressed because audio emissions are disabled",
      state,
      rawLocator?.href ?? nav.currentLocator.href
    );
    return;
  }
  const locator = rawLocator ?? nav.currentLocator;
  if (mapper) {
    const { stateLocator, textLocator, publicTextLocator } = mapper(nav, locator);
    // Compute publication-wide totalProgression from the AUDIO locator, not the
    // mapped state locator. The mapper rewrites the locator to the text href
    // (so the player highlights the right element), but computeTotalProgression
    // keys on the audio reading order — passing the text-href stateLocator would
    // never match and yield `undefined`, leaving totalProgression null on the
    // emitted currentLocator. The raw `locator` still carries the audio href + time.
    const enrichedStateLocator = withTotalProgression(
      stateLocator,
      computeTotalProgression(locator)
    );
    const totalProgressDuration = makeTotalProgressDurationMs(
      enrichedStateLocator,
      publicationTotalDurationMs
    );
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enrichedStateLocator, totalProgressDuration, publicationTotalDurationMs)
    );
    const emittedPublicLocator = publicTextLocator ?? textLocator;
    if (emittedPublicLocator) {
      // Use serialize() so otherLocations Map entries (e.g. cssSelector) reach Dart.
      window.updateTextLocator?.(JSON.stringify(emittedPublicLocator.serialize()));
    }
    if (textLocator) {
      onTextLocatorChanged?.(textLocator, undefined);
    }
  } else {
    const enriched = withTocHref(
      withTotalProgression(locator, computeTotalProgression(locator)),
      getTocHref?.()
    );
    const totalProgressDuration = makeTotalProgressDurationMs(
      enriched,
      publicationTotalDurationMs
    );
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enriched, totalProgressDuration, publicationTotalDurationMs)
    );
    if (alsoText) {
      window.updateTextLocator?.(JSON.stringify(enriched.serialize()));
    }
  }
}

/**
 * Resolves the absolute URL ts-toolkit's `AudioNavigator` assigned to
 * `mediaElement.src` for `href`, for use as the HTTP probe target. Reuses the
 * same `findLinkByHref` + `Link.toURL(baseURL)` pattern as
 * `ReadiumReader.getResourceUrl` — the only other place this plugin resolves
 * a publication-relative href to an absolute resource URL.
 *
 * Returns `undefined` when no matching link exists or it has no resolvable
 * URL (e.g. malformed manifest) — callers should skip the probe in that case.
 */
function resolveAudioResourceUrl(
  publication: ReadiumPublication,
  href: string
): string | undefined {
  const link = findLinkByHref(publication.allLinks, href);
  return link?.toURL(publication.baseURL) ?? undefined;
}

/**
 * Runs the HTTP diagnostic probe (see `AudioStreamHttpProbe.ts`) ahead of
 * classification-based dispatch, then hands off to
 * `AudioStreamRecoveryController.handle`.
 *
 * The probe only runs when it could change the outcome: skipped entirely for
 * `MEDIA_ERR_ABORTED` (already `ignore`, and firing a CORS fetch during
 * teardown/seek would be pure overhead) and `MEDIA_ERR_DECODE` (already a
 * conclusive terminal failure — a bad HTTP status can't explain a decode
 * error, and a *good* status would be misleading: the file is reachable but
 * still unplayable). For every other code the probe result — when conclusive
 * — supersedes the MediaError-only classification; an inconclusive probe
 * (timeout/thrown-while-online/opaque) falls back to it unchanged.
 */
async function handleAudioStreamError(
  mediaError: unknown,
  href: string,
  publication: ReadiumPublication,
  recovery: AudioStreamRecoveryController,
  message: string
): Promise<void> {
  const fallback = classifyAudioStreamError(mediaError);
  const code = (mediaError as MediaErrorLike | null | undefined)?.code;

  let action: AudioStreamErrorAction = fallback;
  if (code !== MEDIA_ERR_ABORTED && code !== MEDIA_ERR_DECODE) {
    const url = resolveAudioResourceUrl(publication, href);
    if (url) {
      const probed = await probeAudioStreamHttpStatus(url);
      if (probed) action = probed;
    }
  }

  recovery.handle(message, action, href);
}

/**
 * Rebuilds the `AudioNavigator` at `href` (the ts-toolkit engine has no
 * in-place re-prepare API, so — mirroring iOS/Android — recovery tears down
 * and reconstructs it) and verifies playback position actually advances
 * within `connectionTimeoutMs`. Being in a "ready"/"playing" state alone is
 * not a reliable recovery signal (mirrors Android's `playbackAdvanced`).
 * `connectionTimeoutMs` bounds both phases of the attempt: the rebuild itself
 * (via `withTimeout` below) and, separately, this post-rebuild verification.
 *
 * On success, `onNavReplaced` updates the enclosing `create()` closure's
 * `nav` binding so subsequent listener callbacks (positionChanged, etc.)
 * operate on the freshly-built navigator.
 *
 * @param getLastLocator Reads the *current* locator (with its time fragment)
 *   from the still-live (about to be torn down) navigator at rebuild time —
 *   NOT the original `initialPosition` the session started at, which would
 *   resume at the wrong timestamp after playback has progressed.
 * @param teardownCurrent Stops/destroys the still-live navigator being
 *   replaced. Called after `getLastLocator()` reads it, before the
 *   replacement is built — otherwise both elements can play concurrently.
 * @param recoveryController The session's existing controller, threaded into
 *   the rebuilt navigator's `create()` so its listeners share this loop's
 *   suppression/latch state instead of getting a fresh, orphaned instance.
 */
async function rebuildAndVerifyPlayback(
  href: string,
  publication: ReadiumPublication,
  getLastLocator: () => Locator | undefined,
  teardownCurrent: () => void,
  preferencesJsonString: string,
  setNav: (nav: AudioNavigator) => void,
  pollIntervalOverrideMs: number | undefined,
  bridge: ReadiumBridge,
  recoveryController: AudioStreamRecoveryController,
  onNavReplaced: (nav: AudioNavigator) => void,
  connectionTimeoutMs: number,
  isDisposed: () => boolean
): Promise<boolean> {
  if (isDisposed()) return false;
  const lastPosition = getLastLocator();
  teardownCurrent();
  const resumeLocator = new Locator({
    href,
    type: "audio/mpeg",
    locations: lastPosition?.locations,
  });

  let rebuilt: AudioNavigator | undefined;
  let attemptCancelled = false;
  try {
    await withTimeout(
      FlutterAudioNavigator.create(
        publication,
        resumeLocator,
        preferencesJsonString,
        (n) => {
          if (attemptCancelled || isDisposed()) {
            n.stop();
            n.destroy();
            return;
          }
          rebuilt = n;
          onNavReplaced(n);
          setNav(n);
        },
        undefined,
        undefined,
        pollIntervalOverrideMs,
        bridge,
        false,
        recoveryController
      ),
      connectionTimeoutMs,
      `Timed out rebuilding audio playback after ${connectionTimeoutMs / 1000}s`
    );
  } catch (e) {
    attemptCancelled = true;
    log.error("rebuildAndVerifyPlayback: rebuild failed", e);
    return false;
  }
  if (!rebuilt || isDisposed()) return false;

  rebuilt.play();

  const startOffset = rebuilt.currentTime;
  const deadline = Date.now() + connectionTimeoutMs;
  while (Date.now() < deadline && !isDisposed()) {
    if (rebuilt.currentTime > startOffset + RECOVERY_VERIFY_MIN_ADVANCE_S) {
      return true;
    }
    await sleep(RECOVERY_VERIFY_POLL_MS);
  }
  return false;
}

export class FlutterAudioNavigator {
  // This class is a static factory only. The constructed navigator is delivered
  // via the `setNav` callback so that ReadiumReader can hold it as the raw
  // upstream type (AudioNavigator) without wrapping.

  /**
   * Recovery controller for the current plain-audiobook session, if any.
   * Scoped module-level (mirroring `_emissionsEnabled`) rather than per-`create()`
   * closure so `retryAfterFailure` can reach it after a rebuild has replaced
   * the in-flight `create()` call's local state.
   *
   * Only wired for the plain audiobook path (no `locatorMapper`) — Media
   * Overlay / TTS sessions are out of scope for this parity pass.
   */
  private static _recovery: AudioStreamRecoveryController | undefined;
  /** Incremented on close/stop so stale async callbacks can self-suppress. */
  private static _sessionGeneration = 0;

  /**
   * Clears the terminal-failure latch and rebuilds playback at the last known
   * locator. Mirrors iOS/Android's `play()`-after-failure contract. No-ops if
   * there is no active recovery controller or it isn't currently latched.
   */
  static retryAfterFailure(): void {
    this._recovery?.clearFailure();
  }

  /** True while the current audiobook session is latched in terminal failure. */
  static isTerminallyFailed(): boolean {
    return this._recovery?.isTerminallyFailed() ?? false;
  }

  /** Clears any recovery state. Call when a session ends (stop/closePublication)
   *  so a stale latch/controller can't leak into the next audiobook session. */
  static resetRecovery(): void {
    this._sessionGeneration += 1;
    this._recovery?.dispose();
    this._recovery = undefined;
  }

  // See Readium's guide on ts-toolkit AudioNavigator configuration:
  // https://github.com/readium/ts-toolkit/blob/develop/navigator/docs/audio/ConfiguringAudioNavigator.md
  static async create(
    publication: ReadiumPublication,
    initialPosition: Locator | undefined,
    preferencesJsonString: string,
    setNav: (nav: AudioNavigator) => void,
    locatorMapper?: AudioLocatorMapper,
    onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void,
    /** Override the poll interval (ms) regardless of preferences. Used by media
     *  overlay sessions where cue synchronisation requires much finer granularity
     *  than the Dart-side `updateIntervalSecs` preference (which controls the
     *  progress bar, not cue timing). */
    pollIntervalOverrideMs?: number,
    /** Bridge used to emit streaming-failure error events. Only consulted on
     *  the plain audiobook path (no `locatorMapper`) — pass it from
     *  `ReadiumReader` to enable retry/failure recovery for that session. */
    bridge?: ReadiumBridge,
    /** Internal: recovery rebuild timeouts are failed attempts, not initial-open errors. */
    emitCreateTimeoutError = true,
    /** Internal: when rebuilding during recovery, reuse the session's existing
     *  controller instead of constructing a new one — a fresh controller would
     *  silently replace `_recovery` and reset its attempt budget/latch. */
    recoveryController?: AudioStreamRecoveryController
  ): Promise<void> {
    const tracks = publication.readingOrder.items.length;
    log.info(
      `Initializing AudioNavigator with ${tracks} track(s)`,
      initialPosition
        ? `from ${initialPosition.href} ${initialPosition.locations?.fragments?.[0] ?? ""}`
        : "(no initial position — starting at first track)",
      locatorMapper ? "[Media Overlay mapper attached]" : "",
      pollIntervalOverrideMs != null ? `[pollInterval override: ${pollIntervalOverrideMs}ms]` : ""
    );

    // A fresh session: re-enable emissions (closePublication disables them to
    // suppress post-close stragglers from a previous navigator).
    const sessionGeneration = FlutterAudioNavigator._sessionGeneration;
    _emissionsEnabled = true;
    const isDisposed = () =>
      FlutterAudioNavigator._sessionGeneration !== sessionGeneration || !_emissionsEnabled;

    const basePrefs = audioPreferencesFromJson(preferencesJsonString);
    if (pollIntervalOverrideMs != null) {
      basePrefs.pollInterval = pollIntervalOverrideMs;
    }
    const configuration: AudioNavigatorConfiguration = {
      preferences: basePrefs,
      defaults: {
        volume: 1.0,
        playbackRate: 1.0,
        preservePitch: true,
        skipBackwardInterval: 10,
        skipForwardInterval: 30,
        pollInterval: 1000,
        autoPlay: true, // Auto-advance to next track by default.
        enableMediaSession: true, // Whether to integrate with the browser's Media Session API
      },
    };

    const computeTotalProgression = makeAudioTotalProgressionFn(publication);
    const publicationTotalDurationMs = makePublicationTotalDurationMs(publication);

    // Build the publication timeline so we can extract the current ToC chapter
    // href from `timelineItemChanged` events. Only used on the plain audiobook
    // path (no locatorMapper); Media Overlay items already carry `tocHref` via
    // `SyncNarrationItem.tocHref` (enriched by `enrichItemsWithToc`).
    const timeline = locatorMapper ? undefined : Timeline.build(publication);
    let currentTocHref: string | undefined;
    const getTocHref = timeline ? () => currentTocHref : undefined;

    // Assigned after listener construction. Some timeout/error paths can run
    // before assignment, so cleanup guards every direct use.
    let nav: AudioNavigator | undefined;
    let createCancelled = false;
    let lastPositionLogKey = "";

    const recoveryPolicy = getCurrentAudioRecoveryPolicy();
    // Stall watchdog state: the browser's own `stalled` event fires quickly (~3s) and is
    // only an early *detection* signal that data stopped flowing — not the escalation
    // threshold. Mirrors iOS/Android: escalation waits for the full `stallTimeoutSeconds`
    // of the offset genuinely not advancing while playback is intended, so all three
    // platforms present a consistent ~stallTimeout × maxAttempts UX bar.
    let stallWatchdogTimer: ReturnType<typeof setTimeout> | undefined;
    let lastAdvanceOffset: number | undefined;

    function clearStallWatchdog(): void {
      if (stallWatchdogTimer !== undefined) {
        clearTimeout(stallWatchdogTimer);
        stallWatchdogTimer = undefined;
      }
    }

    /** (Re)arms the watchdog: fires after `stallTimeoutSeconds` unless reset first by another offset advance. */
    function armStallWatchdog(onStalled: () => void): void {
      clearStallWatchdog();
      stallWatchdogTimer = setTimeout(onStalled, recoveryPolicy.stallTimeoutSeconds * 1000);
    }

    /**
     * Called on every `timeupdate`-driven position change while playback is intended: resets
     * the watchdog whenever the offset actually moves, and arms it on the first observation.
     */
    function noteOffsetAdvance(currentOffset: number, onStalled: () => void): void {
      if (lastAdvanceOffset === undefined || currentOffset > lastAdvanceOffset + 0.1) {
        lastAdvanceOffset = currentOffset;
        armStallWatchdog(onStalled);
      }
    }

    // Recovery is only wired for the plain audiobook path. Media Overlay/TTS
    // sessions (locatorMapper present) are out of scope for this parity pass —
    // rebuilding mid-sync-narration would require re-deriving the mapper's
    // internal cue state, which the current AudioLocatorMapper contract does
    // not expose a way to resume.
    //
    // `recoveryController`, when passed (the inner call from
    // `rebuildAndVerifyPlayback`), is reused rather than replaced — a fresh
    // controller would silently orphan `_recovery`'s attempt budget/latch.
    let recovery: AudioStreamRecoveryController | undefined;
    if (!locatorMapper && bridge) {
      recovery = recoveryController ?? new AudioStreamRecoveryController(
        {
          emitError: (message, code, data) => bridge.emitError(message, code, data),
          setPinnedState: (state) => {
            if (isDisposed()) return;
            if (!nav) return;
            window.updateTimebasedPlayerState?.(buildStatePayload(state, nav));
          },
          stopPlayback: () => {
            if (isDisposed()) return;
            nav?.stop();
          },
          delay: sleep,
          rebuildAndVerify: (href) =>
            rebuildAndVerifyPlayback(
              href,
              publication,
              () => nav?.currentLocator,
              () => { nav?.stop(); nav?.destroy(); },
              preferencesJsonString,
              setNav,
              pollIntervalOverrideMs,
              bridge,
              recovery!,
              (n) => { nav = n; },
              recoveryPolicy.connectionTimeoutSeconds * 1000,
              isDisposed
            ),
        },
        getCurrentAudioRecoveryPolicy()
      );
      FlutterAudioNavigator._recovery = recovery;
    }

    // Local emit shorthand — captures the 5 context args so each listener
    // only names the state, locator, and alsoText flag it actually varies.
    const emit = (
      state: string,
      locator: Locator | undefined,
      alsoText: boolean
    ) => {
      if (!nav) return;
      _emitState(
        state,
        nav,
        locator,
        locatorMapper,
        alsoText,
        computeTotalProgression,
        publicationTotalDurationMs,
        onTextLocatorChanged,
        getTocHref
      );
    };

    // Promise that resolves once the first track is loaded and the navigator is
    // ready for playback. Callers awaiting create() will block until this point,
    // preventing race conditions where Dart calls play() before the navigator is set.
    const ready = new Promise<void>((resolve) => {
      let resolved = false;

      const listeners: AudioNavigatorListeners = {
        trackLoaded: (_media) => {
          if (createCancelled || isDisposed()) {
            nav?.stop();
            nav?.destroy();
            resolve();
            return;
          }
          if (!nav) return;
          if (!resolved) {
            resolved = true;
            log.info("AudioNavigator ready (first track loaded)");
            setNav(nav);
            resolve();
          }
        },
        positionChanged: (locator) => {
          if (!nav) return;
          const time = locator.locations?.time?.() ?? nav.currentTime;
          const key = `${locator.href}#${Math.floor(time)}`;
          if (key !== lastPositionLogKey) {
            lastPositionLogKey = key;
            log.debug("positionChanged", locator.href, `t=${time.toFixed(2)}`, nav.isPlaying ? "playing" : "paused");
          }
          emit(nav.isPlaying ? "playing" : "paused", locator, /* alsoText */ true);

          if (recovery && !recovery.isSuppressed()) {
            if (nav.isPlaying) {
              noteOffsetAdvance(time, () => {
                if (recovery!.isSuppressed()) return;
                log.warn(`Playback stalled: offset didn't advance within ${recoveryPolicy.stallTimeoutSeconds}s`);
                recovery!.handle(
                  `Playback stalled (offset frozen for ${recoveryPolicy.stallTimeoutSeconds}s)`,
                  AudioStreamErrorAction.retry(),
                  locator.href
                );
              });
            } else {
              clearStallWatchdog();
              lastAdvanceOffset = undefined;
            }
          }
        },
        timelineItemChanged: (item) => {
          if (timeline && item) {
            const link = timeline.linkFor(item);
            currentTocHref = link?.href;
            log.debug("timelineItemChanged", item.title, "→ tocHref:", currentTocHref ?? "(none)");
          }
        },
        play: (locator) => {
          log.info("play event", locator?.href, locator?.locations?.fragments?.[0] ?? "");
          emit("playing", locator, false);
        },
        pause: (locator) => {
          log.info("pause event", locator?.href, locator?.locations?.fragments?.[0] ?? "");
          clearStallWatchdog();
          lastAdvanceOffset = undefined;
          emit("paused", locator, false);
        },
        trackEnded: (locator) => {
          if (!nav) return;
          // Only emit "ended" when the publication is truly finished (last track).
          // Intermediate track-ends are followed by auto-advance; emitting "ended"
          // would cause Dart-side to close the player prematurely.
          if (!nav.canGoForward) {
            log.info("Publication ended (last track)");
            clearStallWatchdog();
            lastAdvanceOffset = undefined;
            emit("ended", locator, false);
          } else {
            log.debug("Track ended, auto-advancing to next track");
          }
        },
        stalled: (isStalled) => {
          if (!nav) return;
          // Suppress the underlying navigator's own loading/playing/paused churn
          // while a recovery attempt is in flight — only the pinned "loading"
          // state (emitted by the recovery controller) should reach the bridge.
          if (recovery?.isSuppressed()) return;
          log.debug(isStalled ? "Playback stalled (buffering)" : "Stall resolved");
          emit(isStalled ? "loading" : nav.isPlaying ? "playing" : "paused", undefined, false);
        },
        error: (mediaError, locator) => {
          if (!nav) return;
          log.error("AudioNavigator error:", mediaError, "locator:", locator?.href);
          clearStallWatchdog();
          lastAdvanceOffset = undefined;
          if (!recovery) {
            // No recovery wired (Media Overlay/TTS session): fall back to the
            // previous unconditional "failure" emission.
            emit("failure", locator, false);
            return;
          }
          const href = (locator ?? nav.currentLocator).href;
          const message = `AudioNavigator error (code=${(mediaError as { code?: number })?.code ?? "unknown"})`;
          void handleAudioStreamError(mediaError, href, publication, recovery, message);
        },
        metadataLoaded: (_metadata) => {},
        seeking: (_isSeeking) => {},
        seekable: (_seekable) => {},
        contentProtection: (_type, _data) => {},
        peripheral: (_data) => {},
        contextMenu: (_data) => {},
        remotePlaybackStateChanged: (_state) => {},
      };

      nav = new AudioNavigator(publication, listeners, initialPosition, configuration);
    });

    try {
      return await withTimeout(
        ready,
        recoveryPolicy.connectionTimeoutSeconds * 1000,
        `Timed out preparing audio playback after ${recoveryPolicy.connectionTimeoutSeconds}s`
      );
    } catch (error) {
      const timedOut = error instanceof TimeoutError;
      createCancelled = true;
      clearStallWatchdog();
      if (!isDisposed()) {
        try {
          nav?.stop();
          nav?.destroy();
        } catch (destroyError) {
          log.warn("AudioNavigator cleanup after create timeout failed", destroyError);
        }
        if (timedOut && emitCreateTimeoutError && !locatorMapper) {
          log.warn("AudioNavigator initial create timed out", initialPosition?.href ?? "(initial track)");
        }
      }
      // Give the timeout a typed code so Dart stops matching on the message
      // (was previously string-matched via `_convertToNativeCode`).
      if (timedOut) {
        throw new ReadiumWebError((error as Error).message, ReadiumWebErrorCode.audioStreamNetworkError);
      }
      throw error;
    }
  }
}

// ---------------------------------------------------------------------------
// Test-only exports
//
// The double-underscore prefix marks these as internal — not part of the
// module's public API, only exposed for unit tests in __tests__/.
// ---------------------------------------------------------------------------

export const __testing__ = {
  makeAudioTotalProgressionFn,
  withTocHref,
};
