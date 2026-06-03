// Re-export shim — canonical location is navigators/FlutterEpubNavigator.ts
// and navigators/locatorEnrich.ts.
import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Locator } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";

export { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";
export { enrichWithTotalProgression } from "../navigators/locatorEnrich";

/** Backwards-compatible wrapper around FlutterEpubNavigator.create(). */
export async function initializeEpubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: ReadiumPublication,
  initialPosition: Locator | undefined,
  preferencesJsonString: string,
  setNav: (nav: EpubNavigator | WebPubNavigator) => void,
  setPositions?: (positions: Locator[]) => void
): Promise<void> {
  await FlutterEpubNavigator.create(
    container,
    publication,
    initialPosition,
    preferencesJsonString,
    setNav,
    setPositions
  );
}
