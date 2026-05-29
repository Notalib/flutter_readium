import {
  AudioNavigator,
  AudioNavigatorConfiguration,
  AudioNavigatorListeners,
  IAudioPreferences,
} from "@readium/navigator";
import { Locator, LocatorLocations } from "@readium/shared";
import { normalizeTypes } from "../helpers";
import { createLogger } from "../logger";
import { ReadiumPublication } from "../extensions/ReadiumPublication";

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
function makeAudioTotalProgressionFn(
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
    currentLocator: JSON.parse(JSON.stringify(currentLocator)),
  });
}

// See Readium's guide on ts-toolkit AudioNavigator configuration:
// https://github.com/readium/ts-toolkit/blob/develop/navigator/docs/audio/ConfiguringAudioNavigator.md

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
 * Emits timebased-state + (optionally) text-locator events, applying the
 * locator mapper when one is provided.
 *
 * @param state                  Timebased state string.
 * @param nav                    Active AudioNavigator.
 * @param rawLocator             Raw locator from the listener callback (may be undefined
 *                               for stalled events, in which case nav.currentLocator is used).
 * @param mapper                 Optional mapper (Media Overlay / custom sessions).
 * @param alsoText               When true and no mapper is provided, also emit to
 *                               updateTextLocator (used for positionChanged in plain audio).
 * @param onTextLocatorChanged   Optional callback fired each time a text locator is
 *                               derived from the mapper. Used by Media Overlay to apply
 *                               per-cue decorations without extra locator lookups.
 */
function _emitState(
  state: string,
  nav: AudioNavigator,
  rawLocator: Locator | undefined,
  mapper: AudioLocatorMapper | undefined,
  alsoText: boolean,
  computeTotalProgression: (locator: Locator) => number | undefined,
  onTextLocatorChanged?: (locator: Locator) => void
): void {
  const locator = rawLocator ?? nav.currentLocator;
  if (mapper) {
    const { stateLocator, textLocator } = mapper(nav, locator);
    const enrichedStateLocator = withTotalProgression(
      stateLocator,
      computeTotalProgression(stateLocator)
    );
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enrichedStateLocator)
    );
    if (textLocator) {
      window.updateTextLocator?.(JSON.stringify(textLocator));
      onTextLocatorChanged?.(textLocator);
    }
  } else {
    const enriched = withTotalProgression(
      locator,
      computeTotalProgression(locator)
    );
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, enriched)
    );
    if (alsoText) {
      window.updateTextLocator?.(JSON.stringify(enriched));
    }
  }
}

export async function initializeAudioNavigator(
  publication: ReadiumPublication,
  initialPosition: Locator | undefined,
  preferencesJsonString: string,
  setNav: (nav: AudioNavigator) => void,
  locatorMapper?: AudioLocatorMapper,
  onTextLocatorChanged?: (locator: Locator) => void
): Promise<void> {
  log.info("Initializing AudioNavigator");

  const configuration: AudioNavigatorConfiguration = {
    preferences: preferencesFromString(preferencesJsonString),
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

  // nav is used inside the closure before assignment; TypeScript is fine with
  // this because the listeners are only called after `nav` is assigned below.
  let nav: AudioNavigator;

  // Promise that resolves once the first track is loaded and the navigator is
  // ready for playback. Callers awaiting initializeAudioNavigator will block
  // until this point, preventing race conditions where Dart calls play() before
  // the navigator is set.
  const ready = new Promise<void>((resolve) => {
    let resolved = false;

    const listeners: AudioNavigatorListeners = {
      trackLoaded: (_media) => {
        if (!resolved) {
          resolved = true;
          log.info("AudioNavigator ready (first track loaded)");
          setNav(nav);
          resolve();
        }
      },
      positionChanged: (locator) => {
        _emitState(
          nav.isPlaying ? "playing" : "paused",
          nav, locator, locatorMapper, /* alsoText */ true, computeTotalProgression, onTextLocatorChanged
        );
      },
      timelineItemChanged: (_item) => {},
      play: (locator) => {
        _emitState("playing", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged);
      },
      pause: (locator) => {
        _emitState("paused", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged);
      },
      trackEnded: (locator) => {
        // Only emit "ended" when the publication is truly finished (last track).
        // Intermediate track-ends are followed by auto-advance; emitting "ended"
        // would cause Dart-side to close the player prematurely.
        if (!nav.canGoForward) {
          log.info("Publication ended (last track)");
          _emitState("ended", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged);
        } else {
          log.debug("Track ended, auto-advancing to next track");
        }
      },
      stalled: (isStalled) => {
        log.debug(isStalled ? "Playback stalled (buffering)" : "Stall resolved");
        _emitState(
          isStalled ? "loading" : nav.isPlaying ? "playing" : "paused",
          nav, undefined, locatorMapper, false, computeTotalProgression, onTextLocatorChanged
        );
      },
      error: (_error, locator) => {
        log.error("AudioNavigator error:", _error, "locator:", locator?.href);
        _emitState("failure", nav, locator, locatorMapper, false, computeTotalProgression, onTextLocatorChanged);
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

  await ready;
}
