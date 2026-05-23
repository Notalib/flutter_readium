import {
  AudioNavigator,
  AudioNavigatorConfiguration,
  AudioNavigatorListeners,
  IAudioPreferences,
} from "@readium/navigator";
import { Locator } from "@readium/shared";
import { normalizeTypes } from "../helpers";
import { ReadiumPublication } from "../extensions/ReadiumPublication";

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
  console.log('Parsing AudioPreferences from string', prefs);
  return {
    volume: prefs.volume ?? null,
    playbackRate: prefs.speed ?? null,
    skipBackwardInterval: prefs.seekInterval ?? null,
    skipForwardInterval: prefs.seekInterval ?? null,
    pollInterval:
      prefs.updateIntervalSecs != null
        ? prefs.updateIntervalSecs * 1000
        : null,
    autoPlay: false,
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
 * @param state        Timebased state string.
 * @param nav          Active AudioNavigator.
 * @param rawLocator   Raw locator from the listener callback (may be undefined
 *                     for stalled events, in which case nav.currentLocator is used).
 * @param mapper       Optional mapper (Media Overlay / custom sessions).
 * @param alsoText     When true and no mapper is provided, also emit to
 *                     updateTextLocator (used for positionChanged in plain audio).
 */
function _emitState(
  state: string,
  nav: AudioNavigator,
  rawLocator: Locator | undefined,
  mapper: AudioLocatorMapper | undefined,
  alsoText: boolean
): void {
  const locator = rawLocator ?? nav.currentLocator;
  if (mapper) {
    const { stateLocator, textLocator } = mapper(nav, locator);
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, stateLocator)
    );
    if (textLocator) {
      window.updateTextLocator?.(JSON.stringify(textLocator));
    }
  } else {
    window.updateTimebasedPlayerState?.(
      buildStatePayload(state, nav, locator)
    );
    if (alsoText) {
      window.updateTextLocator?.(JSON.stringify(locator));
    }
  }
}

export async function initializeAudioNavigator(
  publication: ReadiumPublication,
  initialPosition: Locator | undefined,
  preferencesJsonString: string,
  setNav: (nav: AudioNavigator) => void,
  locatorMapper?: AudioLocatorMapper
): Promise<void> {
  console.log("Initializing AudioNavigator");

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

  // nav is used inside the closure before assignment; TypeScript is fine with
  // this because the listeners are only called after `nav` is assigned below.
  let nav: AudioNavigator;

  const listeners: AudioNavigatorListeners = {
    trackLoaded: (_media) => {},
    positionChanged: (locator) => {
      _emitState(
        nav.isPlaying ? "playing" : "paused",
        nav, locator, locatorMapper, /* alsoText */ true
      );
    },
    timelineItemChanged: (_item) => {},
    play: (locator) => {
      _emitState("playing", nav, locator, locatorMapper, false);
    },
    pause: (locator) => {
      _emitState("paused", nav, locator, locatorMapper, false);
    },
    trackEnded: (locator) => {
      _emitState("ended", nav, locator, locatorMapper, false);
    },
    stalled: (isStalled) => {
      _emitState(
        isStalled ? "loading" : nav.isPlaying ? "playing" : "paused",
        nav, undefined, locatorMapper, false
      );
    },
    error: (_error, locator) => {
      _emitState("failure", nav, locator, locatorMapper, false);
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
  setNav(nav);
}
