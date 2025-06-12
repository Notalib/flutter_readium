import {
  TextAlignment,
  Theme,
  IEpubPreferences,
  IEpubDefaults,
  EpubPreferences,
  EpubNavigator,
} from '@readium/navigator';

export function setPreferencesFromString(
  preferencesString: string
): IEpubPreferences {
  const prefs = JSON.parse(preferencesString);

  if (prefs.theme != null) {
    prefs.theme = _themeFromJson(prefs.theme);
  }

  if (prefs.textAlign != null) {
    prefs.textAlign = _textAlignFromJson(prefs.textAlign);
  }

  let preferences: IEpubPreferences = {
    backgroundColor: prefs.backgroundColor ?? null,
    blendFilter: prefs.blendFilter ?? null,
    // need to find out how to ensure reflowable works without refresh
    columnCount: prefs.columnCount ?? null,
    constraint: prefs.constraint ?? null,
    darkenFilter: prefs.darkenFilter ?? null,
    deprecatedFontSize: prefs.deprecatedFontSize ?? null,
    fontFamily: prefs.fontFamily ?? null,
    // FontSize is NOT in pixels or pt!!!
    fontSize: prefs.fontSize ?? null,
    fontSizeNormalize: prefs.fontSizeNormalize ?? null,
    fontOpticalSizing: prefs.fontOpticalSizing ?? null,
    fontWeight: prefs.fontWeight ?? null,
    fontWidth: prefs.fontWidth ?? null,
    hyphens: prefs.hyphens ?? null,
    invertFilter: prefs.invertFilter ?? null,
    invertGaijiFilter: prefs.invertGaijiFilter ?? null,
    iPadOSPatch: prefs.iPadOSPatch ?? null,
    letterSpacing: prefs.letterSpacing ?? null,
    ligatures: prefs.ligatures ?? null,
    lineHeight: prefs.lineHeight ?? null,
    linkColor: prefs.linkColor ?? null,
    noRuby: prefs.noRuby ?? null,
    optimalLineLength: prefs.optimalLineLength ?? null,
    pageGutter: prefs.pageGutter ?? null,
    paragraphIndent: prefs.paragraphIndent ?? null,
    paragraphSpacing: prefs.paragraphSpacing ?? null,
    scroll: prefs.scroll ?? null,
    selectionBackgroundColor: prefs.selectionBackgroundColor ?? null,
    selectionTextColor: prefs.selectionTextColor ?? null,
    textAlign: prefs.textAlign ?? null,
    textColor: prefs.textColor ?? null,
    textNormalization: prefs.textNormalization ?? null,
    theme: prefs.theme ?? null,
    visitedColor: prefs.visitedColor ?? null,
    wordSpacing: prefs.wordSpacing ?? null,
  };

  return preferences;
}

export const defaults: IEpubDefaults = {
  backgroundColor: null,
  blendFilter: true,
  columnCount: 2,
  darkenFilter: 0.5,
  fontFamily: 'Arial',
  fontSize: 1,
  fontWeight: 400,
  fontWidth: 100,
  hyphens: true,
  letterSpacing: 0,
  ligatures: true,
  lineHeight: 1.5,
  linkColor: '#0000ff',
  pageGutter: 10,
  scroll: false,
  selectionBackgroundColor: '#cccccc',
  selectionTextColor: '#000000',
  textAlign: TextAlignment.justify,
  textColor: null,
  textNormalization: true,
  theme: Theme.day,
  visitedColor: '#551a8b',
  wordSpacing: 0,
};

function _themeFromJson(themeString: string): Theme {
  switch (themeString) {
    case 'sepia':
      return Theme.sepia;
    case 'night':
      return Theme.night;
    case 'custom':
      return Theme.custom;
    case 'day':
    default:
      return Theme.day;
  }
}

function _textAlignFromJson(textAlignString: string): TextAlignment {
  switch (textAlignString) {
    case 'left':
      return TextAlignment.left;
    case 'right':
      return TextAlignment.right;
    case 'start':
      return TextAlignment.start;
    case 'justify':
      return TextAlignment.justify;
    default:
      return TextAlignment.left;
  }
}

export function updatePreferences(
  newPreferencesString: string,
  nav: EpubNavigator
) {
  let newPreferences: EpubPreferences = JSON.parse(newPreferencesString);
  if (newPreferences.theme != null) {
    newPreferences.theme = _themeFromJson(newPreferences.theme);
  }
  if (newPreferences.textAlign != null) {
    newPreferences.textAlign = _textAlignFromJson(newPreferences.textAlign);
  }
  nav.submitPreferences(newPreferences);
}
