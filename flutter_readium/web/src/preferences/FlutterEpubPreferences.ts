import {
  EpubNavigator,
  IEpubPreferences,
  IEpubDefaults,
  WebPubNavigator,
  TextAlignment,
} from "@readium/navigator";
import { dartColorToCss } from "../utils/colors";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("EpubPrefs");

// ---------------------------------------------------------------------------
// Shared preference helpers (also re-exported for consumers and barrel)
// ---------------------------------------------------------------------------

export function convertVerticalScroll(prefs: any) {
  if ("verticalScroll" in prefs) {
    prefs.scroll = prefs.verticalScroll;
    delete prefs.verticalScroll;
  }
}

export function textAlignFromJson(textAlignString: string): TextAlignment {
  switch (textAlignString) {
    case "left":
      return TextAlignment.left;
    case "right":
      return TextAlignment.right;
    case "start":
      return TextAlignment.start;
    case "justify":
      return TextAlignment.justify;
    default:
      return TextAlignment.left;
  }
}

export function normalizeTypes(obj: any): any {
  if (Array.isArray(obj)) {
    return obj.map(normalizeTypes);
  } else if (obj !== null && typeof obj === "object") {
    for (const key in obj) {
      if (!obj.hasOwnProperty(key)) continue;
      const value = obj[key];
      if (typeof value === "string") {
        if (value === "true") {
          obj[key] = true;
        } else if (value === "false") {
          obj[key] = false;
        } else if (/^-?\d+(\.\d+)?$/.test(value)) {
          // Only convert if the string is a pure number (int or float)
          obj[key] = value.includes(".")
            ? parseFloat(value)
            : parseInt(value, 10);
        }
      } else if (typeof value === "object" && value !== null) {
        obj[key] = normalizeTypes(value);
      } else if (value === "null" || value == null) {
        delete obj[key];
      }
    }
  }
  return obj;
}

/**
 * Converts the Dart-side EPUBPreferences JSON into Readium's IEpubPreferences.
 *
 * Source of truth: flutter_readium_platform_interface/lib/src/reader/reader_epub_preferences.dart
 *
 * Each entry is documented to mirror EPUBPreferences in Dart. Where the web navigator's
 * API differs from the native (kotlin / swift) Readium toolkits, the difference is
 * called out inline and converted here so that callers can use the same Dart API on
 * every platform.
 *
 * Fields present in the Dart API but unsupported by the web navigator are listed at the
 * end of this function with a brief rationale and dropped from the output.
 */
export function epubPreferencesFromJson(
  rawPrefs: Record<string, unknown>
): IEpubPreferences {
  const prefs: Record<string, unknown> = { ...rawPrefs };

  // Legacy alias: older clients sent `verticalScroll` instead of `scroll`.
  convertVerticalScroll(prefs);

  // Build the output incrementally so unset Dart fields stay `undefined` rather
  // than `null`. The navigator's `merging()` only filters out `undefined`, so
  // explicit `null`s would clobber the previously-submitted preferences.
  const out: IEpubPreferences = {};

  // ---------------------------------------------------------------------------
  // Direct pass-throughs (Dart key === web key, no type change).
  // ---------------------------------------------------------------------------
  /** Default page background color (CSS color string). */
  if (typeof prefs.backgroundColor === "string") out.backgroundColor = dartColorToCss(prefs.backgroundColor);
  /** Font family for text content. */
  if (typeof prefs.fontFamily === "string") out.fontFamily = prefs.fontFamily;
  /** Font weight (CSS `font-weight`, 100–1000). */
  if (typeof prefs.fontWeight === "number") out.fontWeight = prefs.fontWeight;
  /** Hyphenation for text content. Requires publisher styles to be off (native). */
  if (typeof prefs.hyphens === "boolean") out.hyphens = prefs.hyphens;
  /** Letter spacing (rem). */
  if (typeof prefs.letterSpacing === "number") out.letterSpacing = prefs.letterSpacing;
  /** Ligatures. */
  if (typeof prefs.ligatures === "boolean") out.ligatures = prefs.ligatures;
  /** Line height (unitless multiplier). */
  if (typeof prefs.lineHeight === "number") out.lineHeight = prefs.lineHeight;
  /** Text indent for paragraphs (rem). */
  if (typeof prefs.paragraphIndent === "number") out.paragraphIndent = prefs.paragraphIndent;
  /** Paragraph spacing (rem). */
  if (typeof prefs.paragraphSpacing === "number") out.paragraphSpacing = prefs.paragraphSpacing;
  /** Vertical scroll for reflowable content. Default false -> horizontal pagination. */
  if (typeof prefs.scroll === "boolean") out.scroll = prefs.scroll;
  /** Text color. */
  if (typeof prefs.textColor === "string") out.textColor = dartColorToCss(prefs.textColor);
  /** Normalize text styles for accessibility. */
  if (typeof prefs.textNormalization === "boolean") out.textNormalization = prefs.textNormalization;
  /** Space between words (rem). */
  if (typeof prefs.wordSpacing === "number") out.wordSpacing = prefs.wordSpacing;

  // ---------------------------------------------------------------------------
  // Conversions / renames.
  // ---------------------------------------------------------------------------

  /**
   * Number of columns to display in reflowable content.
   * Dart enum (auto/one/two) maps to `number | null`. `auto` is sent explicitly
   * as `null` so the user override is cleared and Readium CSS picks via viewport.
   */
  if (prefs.columnCount !== undefined) out.columnCount = mapColumnCount(prefs.columnCount);

  /**
   * Image filter. Dart's single `imageFilter` enum maps to two distinct toggles on
   * the web side. Only emit fields when the Dart side actually sent `imageFilter`;
   * sending `null` for either when nothing was requested would wipe the existing
   * filter from a prior call.
   *
   * NOTE: this only covers EPUB image filters; the Nota comic-book B/W mode is a
   * separate concern handled via custom CSS injection on native.
   */
  if (prefs.imageFilter !== undefined) {
    const { darkenFilter, invertFilter } = mapImageFilter(prefs.imageFilter);
    out.darkenFilter = darkenFilter;
    out.invertFilter = invertFilter;
  }

  // Font size — Dart sends a ratio (1.0 = default, 1.5 = 150%); forward unchanged.
  if (typeof prefs.fontSize === "number") out.fontSize = prefs.fontSize;

  /**
   * Text alignment. Dart's `TextAlign` (left/right/center/justify/start/end) ->
   * web's `TextAlignment` (left/right/start/justify). `center` and `end` get
   * clamped by helpers.textAlignFromJson.
   */
  if (typeof prefs.textAlign === "string") out.textAlign = textAlignFromJson(prefs.textAlign);

  /**
   * Page margins. Dart's `pageMargins` maps to the upstream's `pageGutter`
   * (horizontal pagination margins; vertical margins in vertical-writing mode).
   * Accept either key for forward compatibility.
   */
  const gutter = prefs.pageGutter ?? prefs.pageMargins;
  if (typeof gutter === "number") out.pageGutter = gutter;

  // ---------------------------------------------------------------------------
  // Dart EPUBPreferences fields NOT supported by the web navigator
  // ---------------------------------------------------------------------------
  // - publisherStyles: native uses this to toggle the publisher CSS layer. The web
  //   navigator does not expose an equivalent toggle; custom CSS overrides are applied
  //   whenever a value is set on IEpubPreferences regardless of this flag.
  // - readingProgression (ltr/rtl): the web navigator derives this from the publication
  //   manifest and does not accept it as a runtime preference.
  // - spread: fixed-layout spread mode is not configurable through IEpubPreferences.
  // - typeScale, verticalText, language: not part of the web navigator preference surface.
  // - blackAndWhiteComicMode, firstElementTopMargin: Nota-specific extensions implemented
  //   on native via custom CSS variables. Not wired through on web yet — would require
  //   custom CSS injection into the EPUB iframe.
  // - disableSynchronization: handled by ReadiumReader (plugin state), not navigator prefs.
  // ---------------------------------------------------------------------------

  return normalizeTypes(out);
}

export function initializeEpubPreferencesFromString(
  preferencesString: string
): IEpubPreferences {
  const prefs = epubPreferencesFromJson(JSON.parse(preferencesString));
  log.debug("Parsed initial preferences", prefs);
  return prefs
}

/**
 * Applies a Dart-side EPUBPreferences JSON string to a live navigator.
 * Performs the same conversion as initialization, so runtime updates and initial
 * preferences are interpreted identically.
 *
 * Important: we pass the plain `IEpubPreferences` shape (not a constructed
 * `EpubPreferences` instance) so that only fields the caller explicitly set are
 * merged in. The `EpubPreferences` constructor initialises every field via its
 * `ensure*` guards — which turns `undefined` into `null` — and the navigator's
 * `merging()` only filters out `undefined`, not `null`. Wrapping would therefore
 * wipe every existing preference on each call.
 */
export function setEpubPreferencesFromString(
  preferencesString: string,
  nav: EpubNavigator | WebPubNavigator
): void {
  const preferences = epubPreferencesFromJson(JSON.parse(preferencesString));
  // The union nav.submitPreferences requires `EpubPreferences & WebPubPreferences`,
  // but at runtime both navigators merge from any IEpubPreferences-shaped input.
  // Cast the argument (not the function) so the call stays a method invocation
  // and `this` remains bound to `nav` — extracting it as a free function would
  // break `this._preferences.merging(...)` inside the navigator.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  log.debug("Submitting preferences to navigator", preferences);
  nav.submitPreferences(preferences as any);
}

/**
 * Converts Dart's percentage-style font size (`int`, e.g. `120` for 120%) into the
 * ratio the web navigator expects (`1.2`). Matches the iOS plugin's behavior.
 */
function mapFontSize(value: unknown): number | null {
  if (typeof value === "number") return value / 100;
  return null;
}

/** Maps Dart's `EpubColumnCount` enum (canonical `auto`/`1`/`2`) to the web's `number | null`. */
function mapColumnCount(value: unknown): number | null {
  switch (value) {
    // "1"/"2" are the canonical Readium values; "one"/"two" are kept for
    // backward tolerance with any legacy senders.
    case "1":
    case "one":
      return 1;
    case "2":
    case "two":
      return 2;
    case "auto":
      return null;
    default:
      // Tolerate a raw number (e.g. from internal callers) — anything else is unset.
      return typeof value === "number" ? value : null;
  }
}

/** Maps Dart's `EpubImageFilter` enum (darken/invert) to web's `darkenFilter`/`invertFilter`. */
function mapImageFilter(value: unknown): {
  darkenFilter: boolean | null;
  invertFilter: boolean | null;
} {
  switch (value) {
    case "darken":
      return { darkenFilter: true, invertFilter: null };
    case "invert":
      return { darkenFilter: null, invertFilter: true };
    default:
      return { darkenFilter: null, invertFilter: null };
  }
}

// TODO: are these the defaults we want in the plugin? Seems random.
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
