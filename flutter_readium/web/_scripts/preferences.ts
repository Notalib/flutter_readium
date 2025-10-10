import {
  TextAlignment,
  IEpubPreferences,
  IEpubDefaults,
  EpubNavigator,
} from '@readium/navigator';

export function initializePreferencesFromString(
  preferencesString: string
): IEpubPreferences {
  const prefs = JSON.parse(preferencesString);

  convertVerticalScroll(prefs);

  if (prefs.textAlign != null) {
    prefs.textAlign = _textAlignFromJson(prefs.textAlign);
  }

  let preferences: IEpubPreferences = {
    backgroundColor: prefs.backgroundColor ?? null,
    blendFilter: prefs.blendFilter ?? null,
    columnCount: prefs.columnCount ?? null,
    constraint: prefs.constraint ?? null,
    darkenFilter: prefs.darkenFilter ?? null,
    deprecatedFontSize: prefs.deprecatedFontSize ?? null,
    fontFamily: prefs.fontFamily ?? null,
    // FontSize is NOT in pixels or pt
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
    // on native there is no pageGutter but pageMargins and my understanding is that it is the same
    // as pageMargins feels more descriptive I have chosen to use that and convert it here to pageGutter
    pageGutter: prefs.pageMargins ?? null,
    paragraphIndent: prefs.paragraphIndent ?? null,
    paragraphSpacing: prefs.paragraphSpacing ?? null,
    scroll: prefs.scroll ?? null,
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
  visitedColor: '#551a8b',
  wordSpacing: 0,
};

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

function convertVerticalScroll(prefs: any) {
  if ('verticalScroll' in prefs) {
    prefs.scroll = prefs.verticalScroll;
    delete prefs.verticalScroll;
  }
}

function normalizeTypes(obj: any): any {
  if (Array.isArray(obj)) {
    return obj.map(normalizeTypes);
  } else if (obj !== null && typeof obj === 'object') {
    for (const key in obj) {
      if (!obj.hasOwnProperty(key)) continue;
      const value = obj[key];
      if (typeof value === 'string') {
        if (value === 'true') {
          obj[key] = true;
        } else if (value === 'false') {
          obj[key] = false;
        } else if (/^-?\d+(\.\d+)?$/.test(value)) {
          // Only convert if the string is a pure number (int or float)
          obj[key] = value.includes('.')
            ? parseFloat(value)
            : parseInt(value, 10);
        }
      } else if (typeof value === 'object' && value !== null) {
        obj[key] = normalizeTypes(value);
      }
    }
  }
  return obj;
}

export function setPreferencesFromString(
  newPreferencesString: string,
  nav: EpubNavigator
) {
  let newPreferences = JSON.parse(newPreferencesString);

  convertVerticalScroll(newPreferences);

  if (newPreferences.textAlign != null) {
    newPreferences.textAlign = _textAlignFromJson(newPreferences.textAlign);
  }
  if (newPreferences.pageMargins != null) {
    newPreferences.pageGutter = newPreferences.pageMargins;
    delete newPreferences.pageMargins;
  }

  newPreferences = normalizeTypes(newPreferences);

  nav.submitPreferences(newPreferences);
}
