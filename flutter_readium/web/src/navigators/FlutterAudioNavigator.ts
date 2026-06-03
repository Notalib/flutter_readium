import {
  AudioNavigator,
  AudioNavigatorConfiguration,
  AudioNavigatorListeners,
  IAudioPreferences,
} from "@readium/navigator";
import { Locator, LocatorLocations, Timeline } from "@readium/shared";
import { normalizeTypes } from "../helpers";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

const log = createLogger("AudioNav");

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
  locator?: Locator
): string {
  const currentLocator = locator ?? nav.currentLocator;
  return JSON.stringify({
    state,
    currentOffset: Math.round(nav.currentTime * 1000),
    currentDuration: nav.duration > 0 ? Math.round(nav.duration * 1000) : null,
    // Use serialize() so otherLocations Map entries are inlined into locations.
    // Plain JSON.stringify drops Map entries silently.
    currentLocator: currentLocator?.serialize(),
  });
}

// Maps Dart AudioPreferences JSON keys to IAudioPreferences.
// Dart "speed" -> TS "playbackRate"; Dart "seekInterval" (s) -> TS skip intervals (s);
// Dart "updateIntervalSecs" (s) -> TS "pollInterval" (ms).
function preferencesFromString(preferencesString: string): IAudioPreferences {
  const prefs = normalizeTypes(JSON.parse(preferencesString));
  log.debug("Parsed AudioPreferences", prefs);
  return {
    volume: prefs.volume ?? null,
    playbackRate: prefs.speed ?? null,
    skipBackwardInterval: prefs.seekInterval ?? null,
    skipForwardInterval: prefs.seekInterval ?? null,
    pollInterval:
      prefs.updateIntervalSecs != null
        ? prefs.updateIntervalSecs * 1000
        : null,
    autoPlay: true,
  };
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
) => { stateLocator: Locator; textLocator?: Locator };

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
    if (resumePlaying) {
      if (nav.isPlaying) nav.pause(); // force a paused→playing transition
      nav.play();
    }
    return Promise.resolve();
  }

  // Pausing here (when playing) guarantees the post-seek play() restarts the
  // upstream position poll; go() alone would leave it stopped.
  if (nav.isPlaying) nav.pause();
  return nav.go(audioLocator, false, (ok) => {
    if (!ok) {
      log.warn("seekAudioAndResume: audio seek failed for", audioLocator.href);
      return;
    }
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
  _emissionsEnabled = enabled;
}

function _emitState(
  state: string,
  nav: AudioNavigator,
  rawLocator: Locator | undefined,
  mapper: AudioLocatorMapper | undefined,
  alsoText: boolean,
  computeTotalProgression: (locator: Locator) => number | undefined,
  onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void,
  getTocHref?: () => string | undefined
): void {
  if (!_emissionsEnabled) return;
  const locator = rawLocator ?? nav.currentLocator;
  if (mapper) {
    const { stateLocator, textLocator } = mapper(nav, locator);
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
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enrichedStateLocator)
    );
    if (textLocator) {
      // Use serialize() so otherLocations Map entries (e.g. cssSelector) reach Dart.
      window.updateTextLocator?.(JSON.stringify(textLocator.serialize()));
      onTextLocatorChanged?.(textLocator, undefined);
    }
  } else {
    const enriched = withTocHref(
      withTotalProgression(locator, computeTotalProgression(locator)),
      getTocHref?.()
    );
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enriched)
    );
    if (alsoText) {
      window.updateTextLocator?.(JSON.stringify(enriched.serialize()));
    }
  }
}

export class FlutterAudioNavigator {
  readonly underlying: AudioNavigator;

  private constructor(nav: AudioNavigator) {
    this.underlying = nav;
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
    pollIntervalOverrideMs?: number
  ): Promise<FlutterAudioNavigator> {
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
    _emissionsEnabled = true;

    const basePrefs = preferencesFromString(preferencesJsonString);
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

    // Build the publication timeline so we can extract the current ToC chapter
    // href from `timelineItemChanged` events. Only used on the plain audiobook
    // path (no locatorMapper); Media Overlay items already carry `tocHref` via
    // `SyncNarrationItem.tocHref` (enriched by `enrichItemsWithToc`).
    const timeline = locatorMapper ? undefined : Timeline.build(publication);
    let currentTocHref: string | undefined;
    const getTocHref = timeline ? () => currentTocHref : undefined;

    // nav is used inside the closure before assignment; TypeScript is fine with
    // this because the listeners are only called after `nav` is assigned below.
    let nav: AudioNavigator;

    // Promise that resolves once the first track is loaded and the navigator is
    // ready for playback. Callers awaiting create() will block until this point,
    // preventing race conditions where Dart calls play() before the navigator is set.
    const ready = new Promise<FlutterAudioNavigator>((resolve) => {
      let resolved = false;

      const listeners: AudioNavigatorListeners = {
        trackLoaded: (_media) => {
          if (!resolved) {
            resolved = true;
            log.info("AudioNavigator ready (first track loaded)");
            setNav(nav);
            resolve(new FlutterAudioNavigator(nav));
          }
        },
        positionChanged: (locator) => {
          _emitState(
            nav.isPlaying ? "playing" : "paused",
            nav, locator, locatorMapper, /* alsoText */ true, computeTotalProgression, onTextLocatorChanged, getTocHref
          );
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
          _emitState("playing", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged, getTocHref);
        },
        pause: (locator) => {
          log.info("pause event", locator?.href, locator?.locations?.fragments?.[0] ?? "");
          _emitState("paused", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged, getTocHref);
        },
        trackEnded: (locator) => {
          // Only emit "ended" when the publication is truly finished (last track).
          // Intermediate track-ends are followed by auto-advance; emitting "ended"
          // would cause Dart-side to close the player prematurely.
          if (!nav.canGoForward) {
            log.info("Publication ended (last track)");
            _emitState("ended", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged, getTocHref);
          } else {
            log.debug("Track ended, auto-advancing to next track");
          }
        },
        stalled: (isStalled) => {
          log.debug(isStalled ? "Playback stalled (buffering)" : "Stall resolved");
          _emitState(
            isStalled ? "loading" : nav.isPlaying ? "playing" : "paused",
            nav, undefined, locatorMapper, false, computeTotalProgression, onTextLocatorChanged, getTocHref
          );
        },
        error: (_error, locator) => {
          log.error("AudioNavigator error:", _error, "locator:", locator?.href);
          _emitState("failure", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged, getTocHref);
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

    return await ready;
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
