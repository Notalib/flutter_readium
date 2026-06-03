// Re-export shim — canonical location is navigators/FlutterWebPubNavigator.ts.
import { WebPubNavigator } from "@readium/navigator";
import { Locator } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { FlutterWebPubNavigator } from "../navigators/FlutterWebPubNavigator";

export { FlutterWebPubNavigator } from "../navigators/FlutterWebPubNavigator";

/** Backwards-compatible wrapper around FlutterWebPubNavigator.create(). */
export async function initializeWebPubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: ReadiumPublication,
  initialPosition: Locator | undefined,
  preferencesJsonString: string,
  setNav: (nav: WebPubNavigator) => void
): Promise<void> {
  await FlutterWebPubNavigator.create(
    container,
    publication,
    initialPosition,
    preferencesJsonString,
    setNav
  );
}
