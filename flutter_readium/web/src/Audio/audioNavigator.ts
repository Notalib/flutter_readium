// Re-export shim — canonical location is navigators/FlutterAudioNavigator.ts.
export {
  FlutterAudioNavigator,
  buildStatePayload,
  seekAudioAndResume,
  setAudioEmissionsEnabled,
  makeAudioTotalProgressionFn,
  withTocHref,
  __testing__,
} from "../navigators/FlutterAudioNavigator";
export type {
  AudioLocatorMapper,
  SeekableAudioNavigator,
} from "../navigators/FlutterAudioNavigator";

import { AudioNavigator } from "@readium/navigator";
import { Locator } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import {
  AudioLocatorMapper,
  FlutterAudioNavigator,
} from "../navigators/FlutterAudioNavigator";

/** Backwards-compatible free-function wrapper around FlutterAudioNavigator.create(). */
export async function initializeAudioNavigator(
  publication: ReadiumPublication,
  initialPosition: Locator | undefined,
  preferencesJsonString: string,
  setNav: (nav: AudioNavigator) => void,
  locatorMapper?: AudioLocatorMapper,
  onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void,
  pollIntervalOverrideMs?: number
): Promise<void> {
  await FlutterAudioNavigator.create(
    publication,
    initialPosition,
    preferencesJsonString,
    setNav,
    locatorMapper,
    onTextLocatorChanged,
    pollIntervalOverrideMs
  );
}
