import {
  TextAlignment,
  IWebPubDefaults,
  IWebPubPreferences,
  WebPubNavigator,
  WebPubPreferences,
} from "@readium/navigator";
import {
  convertVerticalScroll,
  normalizeTypes,
  textAlignFromJson,
} from "../helpers";
import { createLogger } from "../logger";

const log = createLogger("WebPubPrefs");

/**
 * Converts the Dart-side EPUBPreferences JSON into Readium's IWebPubPreferences.
 *
 * Dart only ships an `EPUBPreferences` model (see
 * flutter_readium_platform_interface/lib/src/reader/reader_epub_preferences.dart);
 * we re-use that shape for WebPubs and translate where possible. The upstream
 * `IWebPubPreferences` interface is intentionally a thin subset of
 * `IEpubPreferences` — see WEBPUB_UNSUPPORTED_KEYS below for the fields that
 * have no WebPub equivalent and are silently dropped by the upstream navigator.
 *
 * Notable translations:
 *   - `fontSize` (Dart percentage int, e.g. 120) → `zoom` (ratio in [0.7, 4]),
 *     matching the EPUB mapper's `/100` conversion. WebPub has no `fontSize`
 *     field; `zoom` is the closest analogue (it scales spacing too).
 *   - `verticalScroll` (legacy Dart alias) → `scroll` (then dropped — see below).
 */
export function initializeWebPubPreferencesFromString(
  preferencesString: string
): IWebPubPreferences {
  const prefs = JSON.parse(preferencesString);

  convertVerticalScroll(prefs);

  warnIfUnsupportedKeys(prefs);

  if (prefs.textAlign != null) {
    prefs.textAlign = textAlignFromJson(prefs.textAlign);
  }

  let preferences: IWebPubPreferences = {
    fontFamily: prefs.fontFamily ?? null,
    fontWeight: prefs.fontWeight ?? null,
    hyphens: prefs.hyphens ?? null,
    iOSPatch: prefs.iOSPatch ?? null,
    iPadOSPatch: prefs.iPadOSPatch ?? null,
    letterSpacing: prefs.letterSpacing ?? null,
    ligatures: prefs.ligatures ?? null,
    lineHeight: prefs.lineHeight ?? null,
    noRuby: prefs.noRuby ?? null,
    paragraphIndent: prefs.paragraphIndent ?? null,
    paragraphSpacing: prefs.paragraphSpacing ?? null,
    textAlign: prefs.textAlign ?? null,
    textNormalization: prefs.textNormalization ?? null,
    wordSpacing: prefs.wordSpacing ?? null,
    // Use `fontSize` as a fallback to zoom.
    // It's sent as a percentage int, so we convert to a zoom ratio.
    zoom: prefs.zoom ?? typeof prefs.fontSize === "number"
      ? prefs.fontSize / 100
      : null,
  };

  preferences = normalizeTypes(preferences);

  return preferences;
}

/**
 * Runtime preferences setter — equivalent of `setEpubPreferencesFromString` but
 * for `WebPubNavigator`. The previous code path routed all `setEPUBPreferences`
 * calls through the EPUB mapper, which produced `fontSize` (a ratio) on the
 * output object. `WebPubPreferences`'s constructor only reads the 15 fields it
 * knows about, so the EPUB-shaped output had `fontSize` silently dropped at
 * runtime — meaning text-size changes never took effect on WebPub after
 * initial load.
 */
export function setWebPubPreferencesFromString(
  preferencesString: string,
  nav: WebPubNavigator
): void {
  const prefs = initializeWebPubPreferencesFromString(preferencesString);
  log.debug("Submitting preferences to WebPubNavigator", prefs);
  nav.submitPreferences(new WebPubPreferences(prefs));
}

/**
 * EPUBPreferences keys that the Dart side accepts but the upstream
 * IWebPubPreferences interface has no field for. Sending them is a no-op.
 *
 * Source of truth for the WebPub-supported field set:
 *   node_modules/@readium/navigator/src/webpub/preferences/WebPubPreferences.ts
 *
 * If you need any of these to take effect on a WebPub, the publication must
 * declare `metadata.conformsTo` with the EPUB profile so it routes to
 * `EpubNavigator` instead — see ReadiumReader.openPublication routing.
 */
const WEBPUB_UNSUPPORTED_KEYS = [
  "backgroundColor",
  "textColor",
  "linkColor",
  "visitedColor",
  "selectionBackgroundColor",
  "selectionTextColor",
  "columnCount",
  "scroll",
  "pageGutter",
  "pageMargins",
  "imageFilter",
  "blendFilter",
  "darkenFilter",
  "invertFilter",
  "invertGaijiFilter",
  "constraint",
  "deprecatedFontSize",
  "fontSizeNormalize",
  "fontOpticalSizing",
  "fontWidth",
  "optimalLineLength",
] as const;

function warnIfUnsupportedKeys(prefs: Record<string, unknown>): void {
  const dropped = WEBPUB_UNSUPPORTED_KEYS.filter(
    (k) => prefs[k] !== undefined && prefs[k] !== null
  );
  if (dropped.length > 0) {
    log.warn(
      `Ignoring WebPub-unsupported preferences: ${dropped.join(", ")}. ` +
      "Upstream WebPubPreferences has no equivalent field. Route via the " +
      "EPUB profile (manifest conformsTo) to get full preference support."
    );
  }
}

export const defaults: IWebPubDefaults = {
  //   backgroundColor: null,
  //   blendFilter: true,
  //   columnCount: 2,
  //   darkenFilter: 0.5,
  fontFamily: "Arial",
  //   fontSize: 1,
  fontWeight: 400,
  //   fontWidth: 100,
  hyphens: true,
  letterSpacing: 0,
  ligatures: true,
  lineHeight: 1.5,
  //   linkColor: "#0000ff",
  noRuby: false,
  //   pageGutter: 10,
  paragraphIndent: 0,
  paragraphSpacing: 0,
  //   scroll: false,
  //   selectionBackgroundColor: "#cccccc",
  //   selectionTextColor: "#000000",
  textAlign: TextAlignment.justify,
  //   textColor: null,
  textNormalization: true,
  //   visitedColor: "#551a8b",
  wordSpacing: 0,
  zoom: 1,
};
