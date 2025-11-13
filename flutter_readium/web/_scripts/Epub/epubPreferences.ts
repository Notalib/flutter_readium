import {
  TextAlignment,
  IEpubPreferences,
  IEpubDefaults,
} from "@readium/navigator";
import {
  convertVerticalScroll,
  normalizeTypes,
  textAlignFromJson,
} from "../helpers";

export function initializeEpubPreferencesFromString(
  preferencesString: string
): IEpubPreferences {
  const prefs = JSON.parse(preferencesString);

  convertVerticalScroll(prefs);

  if (prefs.textAlign != null) {
    prefs.textAlign = textAlignFromJson(prefs.textAlign);
  }

  let preferences: IEpubPreferences = {
    backgroundColor: prefs.backgroundColor ?? null,
    blendFilter: prefs.blendFilter ?? null,
    columnCount: prefs.columnCount ?? null,
    // Can find no information on what this does
    constraint: prefs.constraint ?? null,
    darkenFilter: prefs.darkenFilter ?? null,
    deprecatedFontSize: prefs.deprecatedFontSize ?? null,
    fontFamily: prefs.fontFamily ?? null,
    fontSize: prefs.fontSize ?? null,
    fontSizeNormalize: prefs.fontSizeNormalize ?? null,
    fontOpticalSizing: prefs.fontOpticalSizing ?? null,
    fontWeight: prefs.fontWeight ?? null,
    // This says it is taking number but Readium CSS documentation has words like "normal", "condensed", "expanded" and lastly "percentage"
    fontWidth: prefs.fontWidth ?? null,
    hyphens: prefs.hyphens ?? null,
    invertFilter: prefs.invertFilter ?? null,
    invertGaijiFilter: prefs.invertGaijiFilter ?? null,
    iOSPatch: prefs.iOSPatch ?? null,
    iPadOSPatch: prefs.iPadOSPatch ?? null,
    letterSpacing: prefs.letterSpacing ?? null,
    ligatures: prefs.ligatures ?? null,
    lineHeight: prefs.lineHeight ?? null,
    linkColor: prefs.linkColor ?? null,
    maximalLineLength: prefs.maximalLineLength ?? null,
    minimalLineLength: prefs.minimalLineLength ?? null,
    // will hide ruby annotations, but why is this needed?
    noRuby: prefs.noRuby ?? null,
    optimalLineLength: prefs.optimalLineLength ?? null,
    // pageGutter is the page margins for horizontal by default and for vertical in vertical-writing. Added support for pageMargins as an alias for pageGutter.
    pageGutter: prefs.pageGutter ?? prefs.pageMargins ?? null,
    paragraphIndent: prefs.paragraphIndent ?? null,
    paragraphSpacing: prefs.paragraphSpacing ?? null,
    scroll: prefs.scroll ?? null,
    scrollPaddingTop: prefs.scrollPaddingTop ?? null,
    scrollPaddingBottom: prefs.scrollPaddingBottom ?? null,
    selectionBackgroundColor: prefs.selectionBackgroundColor ?? null,
    selectionTextColor: prefs.selectionTextColor ?? null,
    textAlign: prefs.textAlign ?? null,
    textColor: prefs.textColor ?? null,
    textNormalization: prefs.textNormalization ?? null,
    visitedColor: prefs.visitedColor ?? null,
    wordSpacing: prefs.wordSpacing ?? null,
  };

  preferences = normalizeTypes(preferences);

  return preferences;
}

export const defaults: IEpubDefaults = {
  backgroundColor: null,
  blendFilter: true,
  columnCount: 2,
  fontFamily: "Arial",
  fontSize: 1,
  fontWeight: 400,
  hyphens: true,
  ligatures: true,
  lineHeight: 1.5,
  // linkColor: "#0000ff",
  pageGutter: 10,
  scroll: false,
  selectionBackgroundColor: "#cccccc",
  selectionTextColor: "#000000",
  visitedColor: "#551a8b",
  wordSpacing: 0,
};
