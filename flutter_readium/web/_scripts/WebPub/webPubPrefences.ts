import {
  TextAlignment,
  IWebPubDefaults,
  IWebPubPreferences,
} from "@readium/navigator";
import {
  convertVerticalScroll,
  normalizeTypes,
  textAlignFromJson,
} from "../helpers";

export function initializeWebPubPreferencesFromString(
  preferencesString: string
): IWebPubPreferences {
  const prefs = JSON.parse(preferencesString);

  convertVerticalScroll(prefs);

  if (prefs.textAlign != null) {
    prefs.textAlign = textAlignFromJson(prefs.textAlign);
  }

  // I expected that if null then the default would be used but it seems that is not the case
  let preferences: IWebPubPreferences = {
    // backgroundColor: prefs.backgroundColor ?? null,
    // blendFilter: prefs.blendFilter ?? null,
    // columnCount: prefs.columnCount ?? null,
    // constraint: prefs.constraint ?? null,
    // darkenFilter: prefs.darkenFilter ?? null,
    // deprecatedFontSize: prefs.deprecatedFontSize ?? null,
    fontFamily: prefs.fontFamily ?? null,
    // fontSize: prefs.fontSize ?? null,
    // fontSizeNormalize: prefs.fontSizeNormalize ?? null,
    // fontOpticalSizing: prefs.fontOpticalSizing ?? null,
    fontWeight: prefs.fontWeight ?? null,
    // fontWidth: prefs.fontWidth ?? null,
    hyphens: prefs.hyphens ?? null,
    // invertFilter: prefs.invertFilter ?? null,
    // invertGaijiFilter: prefs.invertGaijiFilter ?? null,
    // iPadOSPatch: prefs.iPadOSPatch ?? null,
    letterSpacing: prefs.letterSpacing ?? null,
    ligatures: prefs.ligatures ?? null,
    lineHeight: prefs.lineHeight ?? null,
    // linkColor: prefs.linkColor ?? null,
    noRuby: prefs.noRuby ?? null,
    // optimalLineLength: prefs.optimalLineLength ?? null,
    // pageGutter: prefs.pageMargins ?? null,
    paragraphIndent: prefs.paragraphIndent ?? null,
    paragraphSpacing: prefs.paragraphSpacing ?? null,
    // scroll: prefs.scroll ?? null,
    // selectionBackgroundColor: prefs.selectionBackgroundColor ?? null,
    // selectionTextColor: prefs.selectionTextColor ?? null,
    textAlign: prefs.textAlign ?? null,
    // textColor: prefs.textColor ?? null,
    textNormalization: prefs.textNormalization ?? null,
    // visitedColor: prefs.visitedColor ?? null,
    wordSpacing: prefs.wordSpacing ?? null,
    zoom: prefs.zoom ?? 1,
  };

  preferences = normalizeTypes(preferences);

  return preferences;
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
