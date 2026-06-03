// Re-export barrel — canonical locations are in sub-modules.
// Removed in Phase D step 15 once all consumers are updated.

export { fetchManifest } from "./utils/manifest";
export { dartColorToCss } from "./utils/colors";
export { injectFlutterReadiumHelperScripts } from "./utils/iframeInjection";
export { mediaTypes } from "./utils/ReadiumExtensions";
export {
  UNDERLINE_GROUP_SUFFIX,
  sendDecorate,
  navIframeWindows,
  registerPendingDecorationGroup,
  injectDecorationOverrides,
  highlightSelection,
} from "./decorations/decorationOverrides";
export {
  convertVerticalScroll,
  textAlignFromJson,
  normalizeTypes,
} from "./preferences/FlutterEpubPreferences";

// setPreferencesFromString — will move to preferences/ in Phase D.
import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { convertVerticalScroll, textAlignFromJson, normalizeTypes } from "./preferences/FlutterEpubPreferences";

export function setPreferencesFromString(
  newPreferencesString: string,
  nav: EpubNavigator | WebPubNavigator
) {
  let newPreferences = JSON.parse(newPreferencesString);

  convertVerticalScroll(newPreferences);

  if (newPreferences.textAlign != null) {
    newPreferences.textAlign = textAlignFromJson(newPreferences.textAlign);
  }
  if (newPreferences.pageMargins != null) {
    newPreferences.pageGutter = newPreferences.pageMargins;
    delete newPreferences.pageMargins;
  }

  newPreferences = normalizeTypes(newPreferences);

  // if (nav instanceof EpubNavigator) {
  nav.submitPreferences(newPreferences);
  // }
}

