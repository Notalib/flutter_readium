/**
 * FlutterAudioPreferences — maps Dart AudioPreferences JSON to upstream types.
 *
 * Extracts `preferencesFromString` from FlutterAudioNavigator and the
 * `setAudioPreferences` mapping from the god class into one focused module.
 *
 * Dart key → upstream key:
 *   speed             → playbackRate
 *   seekInterval (s)  → skipBackwardInterval / skipForwardInterval (s)
 *   updateIntervalSecs (s) → pollInterval (ms)
 */

import { AudioNavigator, AudioPreferences, IAudioPreferences } from "@readium/navigator";
import { normalizeTypes } from "./FlutterEpubPreferences";

export { IAudioPreferences };

/** Convert Dart AudioPreferences JSON string to an `IAudioPreferences` object. */
export function audioPreferencesFromJson(preferencesString: string): IAudioPreferences {
  const prefs = normalizeTypes(JSON.parse(preferencesString));
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
 * Parse Dart AudioPreferences JSON and submit them to a live `AudioNavigator`.
 * Mirrors `setAudioPreferences` in the original `_ReadiumReader` god class.
 */
export function applyAudioPreferences(nav: AudioNavigator, preferencesJson: string): void {
  const prefs = JSON.parse(preferencesJson);
  nav.submitPreferences(new AudioPreferences({
    volume: prefs.volume ?? null,
    playbackRate: prefs.speed ?? null,
    skipBackwardInterval: prefs.seekInterval ?? null,
    skipForwardInterval: prefs.seekInterval ?? null,
    pollInterval: prefs.updateIntervalSecs != null
      ? prefs.updateIntervalSecs * 1000
      : null,
  }));
}
