import {
  EpubNavigator,
  TextAlignment,
  WebPubNavigator,
} from "@readium/navigator";
import {
  BasicTextSelection,
  Width,
  Layout,
  Decoration,
} from "@readium/navigator-html-injectables";
import {
  Manifest,
  Link,
  Fetcher,
  HttpFetcher,
  MediaType,
  Locator,
  LocatorText,
} from "@readium/shared";
import { ReadiumPublication } from "./extensions/ReadiumPublication";

export async function fetchManifest(publicationURL: string) {
  const manifestLink = new Link({ href: "manifest.json" });
  const fetcher: Fetcher = new HttpFetcher(undefined, publicationURL);
  const resource = fetcher.get(manifestLink);
  const resourceLink = await resource.link();
  const selfLink = resourceLink.toURL(publicationURL)!;
  const manifest = await resource.readAsJSON().then((response: unknown) => {
    const manifest = Manifest.deserialize(response as string)!;
    manifest.setSelfLink(selfLink);
    return manifest;
  });
  return { manifest, fetcher, selfLink };
}

export function mediaTypes(publication: ReadiumPublication) {
  let selfLinks = publication.manifest.linksWithRel("self");
  let mediaTypesString = selfLinks
    .map((link) => link.type)
    .filter((type): type is string => typeof type === "string");

  let mediaTypes: MediaType[] = mediaTypesString.map((type) =>
    MediaType.parse({ mediaType: type })
  );

  return mediaTypes;
}

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

// NOTE: decoration support here is experimental and will be replaced once
// https://github.com/readium/ts-toolkit/pull/209 (Decorator API) merges.

/**
 * Group-name suffix used to mark decorations whose Dart style is "underline".
 * Underline-style decorations are sent to a separate upstream group so the
 * in-iframe override stylesheet can target them with `[data-group$="__underline"]`
 * (DOM-fallback path) or with a sibling `<style>` augmentation
 * (CSS Custom Highlight API path).
 */
export const UNDERLINE_GROUP_SUFFIX = "__underline";
export const SPOTLIGHT_GROUP_SUFFIX = "__spotlight";

/**
 * Opacity of the dim applied above/below the ruler "reading window" (typoscope).
 * 0 = no dim, 1 = fully black surroundings. Kept moderate so surrounding text
 * stays legible as context rather than being hidden.
 */
const RULER_MASK_DIM = 0.55;

const RULER_BAND_ABOVE_ID = "flutter-readium-ruler-above";
const RULER_BAND_BELOW_ID = "flutter-readium-ruler-below";

// Active ruler ranges keyed by decoration group (e.g. "tts_utterance"), mirrored
// at module level so a freshly-loaded iframe can re-draw the band. Each group
// toggles only its own ranges, so clearing one group never wipes another's band.
const _rulerLocatorsByGroup = new Map<string, Locator[]>();

/**
 * Converts a Dart Color hex string from AARRGGBB to CSS RRGGBBAA format.
 * Dart's Color.toCSS() emits '#AARRGGBB'; CSS expects '#RRGGBBAA'.
 * Shorter or non-hex formats (e.g. '#RGB', '#RRGGBB', named colors) are returned unchanged.
 */
export function dartColorToCss(color: string): string {
  if (/^#[0-9a-fA-F]{8}$/.test(color)) {
    return "#" + color.slice(3) + color.slice(1, 3);
  }
  return color;
}

const SPOTLIGHT_CLASS = "flutter-readium-spotlight";
const AUGMENT_STYLE_ID_PREFIX = "flutter-readium-augment-";
const SPOTLIGHT_STYLE_ID = "flutter-readium-spotlight-style";
const OVERRIDES_STYLE_ID = "flutter-readium-decoration-overrides";
const OVERRIDES_DATASET_FLAG = "flutterReadiumOverrides";
const IFRAME_STATE_KEY = "__flutterReadiumDecorationState";

interface PendingGroup {
  group: string;
  isUnderline: boolean;
  tint: string;
}

interface IframeDecorationState {
  // FIFO of groups whose first-ever `add` is awaiting upstream's <style> creation
  pendingNewGroups: PendingGroup[];
  // Our group name → upstream internal id (e.g. "readium-decoration-3")
  groupInternalId: Map<string, string>;
  // Currently-active spotlight groups (mirrors module state, kept for reapply).
  // A set, not a single value, so independent groups (e.g. tts_utterance and
  // tts_range) can each spotlight without clearing one another.
  spotlightGroups: Set<string>;
}

// Module-level mirror of the active spotlight groups, used to re-apply spotlight
// to iframes that load after a group was activated.
const _spotlightGroups = new Set<string>();

function getIframeState(wnd: Window): IframeDecorationState {
  const w = wnd as any;
  if (!w[IFRAME_STATE_KEY]) {
    w[IFRAME_STATE_KEY] = {
      pendingNewGroups: [],
      groupInternalId: new Map<string, string>(),
      spotlightGroups: new Set<string>(),
    } as IframeDecorationState;
  }
  return w[IFRAME_STATE_KEY];
}

/**
 * Send a "decorate" message to the first content frame of a navigator.
 * Uses the upstream private `nav._cframes[0]?.msg` FrameComms channel — this is
 * intentional: @readium/navigator v2.2.4 does not expose a public decoration API.
 *
 * @param nav  The active EpubNavigator or WebPubNavigator.
 * @param group  Unique decoration group name.
 * @param action  One of "add", "remove", "clear", "update".
 * @param decoration  The decoration payload; may be undefined for "clear".
 */
export function sendDecorate(
  nav: EpubNavigator | WebPubNavigator,
  group: string,
  action: "add" | "remove" | "clear" | "update",
  decoration: Decoration | undefined
): void {
  const frameComms = (nav as any)._cframes?.[0]?.msg;
  if (!frameComms) {
    console.warn("sendDecorate: no FrameComms channel available");
    return;
  }
  frameComms.send("decorate", { group, action, decoration });
}

/**
 * Return the list of content-frame `Window`s for a navigator. Used for fanning
 * out CSS injection / spotlight state to every loaded EPUB iframe.
 */
export function navIframeWindows(
  nav: EpubNavigator | WebPubNavigator
): Window[] {
  const frames: any[] = (nav as any)._cframes ?? [];
  return frames
    .map((f) => f?.window as Window | undefined)
    .filter((w): w is Window => !!w);
}

/**
 * Resolve the DOM element a locator points at within a content document, using
 * the locator's `cssSelector` (stored in `otherLocations`) first, then a
 * fragment id. Returns null if neither resolves.
 */
function resolveLocatorElement(
  doc: Document,
  locator: Locator
): Element | null {
  const css = locator.locations?.otherLocations?.get?.("cssSelector") as
    | string
    | undefined;
  if (css) {
    try {
      const el = doc.querySelector(css);
      if (el) return el;
    } catch {
      /* invalid/unsupported selector — fall through to fragment */
    }
  }
  const fragId = locator.locations?.fragments?.[0]?.replace(/^#/, "");
  if (fragId) return doc.getElementById(fragId);
  return null;
}

/**
 * Ruler "reading mask" / typoscope. Positions two full-viewport-width dim
 * overlays — one above and one below the vertical band spanned by `locators`
 * (the active read-aloud range) — leaving that band clear. Pass an empty array
 * to clear this group's band.
 *
 * Unlike a decoration box-shadow, this is geometry-driven from the resolved
 * range element, so it works in the CSS Custom Highlight API path (where Readium
 * creates no decoration box) as well as the DOM-fallback path. Best suited to
 * scrolled layouts; in paginated/column layouts the document-coordinate maths
 * does not apply. The band is re-computed on each call (i.e. each utterance), so
 * it follows narration; it does not track manual scroll/resize between updates.
 */
export function setRulerBandForGroup(
  nav: EpubNavigator | WebPubNavigator,
  group: string,
  locators: Locator[]
): void {
  if (locators.length > 0) _rulerLocatorsByGroup.set(group, locators);
  else _rulerLocatorsByGroup.delete(group);
  for (const wnd of navIframeWindows(nav)) {
    applyRulerBandToIframe(wnd);
  }
}

function ensureBandEl(doc: Document, id: string): HTMLElement {
  let el = doc.getElementById(id) as HTMLElement | null;
  if (!el) {
    el = doc.createElement("div");
    el.id = id;
    el.dataset.readium = "true";
    el.style.position = "absolute";
    el.style.left = "0";
    el.style.width = "100%";
    el.style.pointerEvents = "none";
    el.style.zIndex = "2147483646";
    el.style.backgroundColor = `rgba(0, 0, 0, ${RULER_MASK_DIM})`;
    doc.body.appendChild(el);
  }
  return el;
}

// Vertical offset of an element from the document origin, summed up the
// offsetParent chain. This matches the coordinate space of an absolutely-
// positioned overlay appended to <body>; `getBoundingClientRect().top + scrollY`
// can diverge from it inside the EPUB iframe's rendering context.
function offsetDocTop(el: HTMLElement): number {
  let y = 0;
  let node: HTMLElement | null = el;
  while (node) {
    y += node.offsetTop;
    node = node.offsetParent as HTMLElement | null;
  }
  return y;
}

function applyRulerBandToIframe(wnd: Window): void {
  const doc = wnd.document;
  if (!doc.body) return;

  // Union the vertical extent of every active ruler range (document coords).
  let top = Infinity;
  let bottom = -Infinity;
  for (const locators of _rulerLocatorsByGroup.values()) {
    for (const loc of locators) {
      const el = resolveLocatorElement(doc, loc) as HTMLElement | null;
      if (!el) continue;
      const elTop = offsetDocTop(el);
      top = Math.min(top, elTop);
      bottom = Math.max(bottom, elTop + el.offsetHeight);
    }
  }

  const above = doc.getElementById(RULER_BAND_ABOVE_ID);
  const below = doc.getElementById(RULER_BAND_BELOW_ID);
  if (!Number.isFinite(top) || !Number.isFinite(bottom)) {
    // No active/resolvable ruler range — remove the overlays.
    above?.remove();
    below?.remove();
    return;
  }

  const docHeight = doc.documentElement.scrollHeight;
  const a = ensureBandEl(doc, RULER_BAND_ABOVE_ID);
  const b = ensureBandEl(doc, RULER_BAND_BELOW_ID);
  a.style.top = "0";
  a.style.height = `${Math.max(0, top)}px`;
  b.style.top = `${bottom}px`;
  b.style.height = `${Math.max(0, docHeight - bottom)}px`;
}

/**
 * Record that the next upstream-created decoration `<style>` element in each
 * iframe should be paired with this group (the parent–side FIFO contract).
 * Called before sending the first `add` to a group; deduplicated against
 * already-paired groups so re-applies on existing groups don't push stale entries.
 */
export function registerPendingDecorationGroup(
  iframes: Window[],
  group: string,
  isUnderline: boolean,
  tint: string
): void {
  for (const wnd of iframes) {
    const state = getIframeState(wnd);
    if (state.groupInternalId.has(group)) continue;
    if (state.pendingNewGroups.some((p) => p.group === group)) continue;
    state.pendingNewGroups.push({ group, isUnderline, tint });
  }
}

/**
 * Activate or deactivate spotlight for a *single* group across the given
 * iframes. While any group is active, all body text is dimmed and every active
 * group's `::highlight()` pseudo-elements restore original colour. Each group
 * toggles only its own contribution, so e.g. clearing `tts_range` never removes
 * a spotlight set by `tts_utterance`.
 *
 * Limitation: spotlight only takes effect when upstream uses the CSS Custom
 * Highlight API path (`"Highlight" in window`). In the DOM-fallback path the
 * `.readium-highlight` box sits *behind* dimmed text, so the dim still shows
 * through. Document this for callers.
 */
export function setSpotlightGroupOnIframes(
  iframes: Window[],
  group: string,
  active: boolean
): void {
  if (active) _spotlightGroups.add(group);
  else _spotlightGroups.delete(group);
  for (const wnd of iframes) {
    const state = getIframeState(wnd);
    if (active) state.spotlightGroups.add(group);
    else state.spotlightGroups.delete(group);
    applySpotlightToIframe(wnd);
  }
}

function applySpotlightToIframe(wnd: Window): void {
  const doc = wnd.document;
  const body = doc.body;
  if (!body) return;
  const state = getIframeState(wnd);
  const groups = state.spotlightGroups;

  body.classList.toggle(SPOTLIGHT_CLASS, groups.size > 0);

  let styleEl = doc.getElementById(SPOTLIGHT_STYLE_ID) as HTMLStyleElement | null;
  if (!styleEl) {
    styleEl = doc.createElement("style");
    styleEl.id = SPOTLIGHT_STYLE_ID;
    styleEl.dataset.readium = "true";
    doc.head.appendChild(styleEl);
  }
  if (groups.size === 0) {
    styleEl.textContent = "";
    return;
  }
  // Collect the upstream internal ids of every active spotlight group (plus its
  // underline sub-group, if any) so each gets its colour/fill restored.
  const internalIds: string[] = [];
  for (const group of groups) {
    const mainId = state.groupInternalId.get(group);
    if (mainId) internalIds.push(mainId);
    const underlineId = state.groupInternalId.get(group + UNDERLINE_GROUP_SUFFIX);
    if (underlineId) internalIds.push(underlineId);
  }

  // Restore the spotlit range's text colour so the body-wide dim doesn't apply
  // inside it. The fill (background-color) is left alone — the caller controls
  // it by passing a tint with the spotlight decoration: a non-transparent tint
  // renders as a fill inside the spotlit range, while a null/transparent tint
  // gives pure dim-outside-only.
  const restoreRules = internalIds
    .map(
      (id) =>
        `body.${SPOTLIGHT_CLASS} ::highlight(${id}) { color: initial !important; }`
    )
    .join("\n  ");

  // Selector specificity must beat ReadiumCSS's `customColors_pref.css` rule
  // (`:root[style*="--USER__textColor"] body { color: ... !important }`, specificity
  // (0,2,1)) which fires on EPUB-profile publications whenever the user has set
  // a text-colour preference. Adding `:not(a)` raises us to (0,3,1) and wins.
  // Without this bump the body-wide dim silently fails on EPUB content while
  // appearing to work on plain WebPub.
  styleEl.textContent = `
    :root[style*="--USER__textColor"] body.${SPOTLIGHT_CLASS} *:not(a),
    body.${SPOTLIGHT_CLASS} *:not(a) {
      color: rgba(0, 0, 0, 0.22) !important;
    }
    ${restoreRules}
  `;
}

/**
 * Pair the just-added upstream `<style id="readium-decoration-N-style">` with
 * the head of the pending-groups queue and (if it's an underline group) emit
 * a sibling `<style>` whose rules win by cascade.
 *
 * The augmented stylesheet overrides the same `::highlight()` pseudo-element.
 * Upstream Readium calls `bi(tint)` to set a contrasting `color` (black or white)
 * on every decoration. For underline groups, that `color` can override the
 * utterance decoration's text colour when both highlights cover the same word
 * (range decorations are registered later and therefore have higher cascade
 * priority). `color: inherit` neutralises that override so the document's
 * natural text colour shows through instead.
 */
function pairWithPendingGroup(wnd: Window, styleEl: HTMLStyleElement): void {
  const state = getIframeState(wnd);
  const pending = state.pendingNewGroups.shift();
  if (!pending) return;
  const internalId = styleEl.id.replace(/-style$/, "");
  state.groupInternalId.set(pending.group, internalId);

  if (pending.isUnderline) {
    const augment = wnd.document.createElement("style");
    augment.dataset.readium = "true";
    augment.id = AUGMENT_STYLE_ID_PREFIX + internalId;
    augment.textContent = `
      ::highlight(${internalId}) {
        color: inherit;
        background-color: transparent;
        text-decoration: underline 0.15em solid ${pending.tint};
      }
    `;
    styleEl.parentNode?.insertBefore(augment, styleEl.nextSibling);
  }

  // Spotlight rules may need to expand now that we know this group's internal id.
  if (state.spotlightGroups.size > 0) {
    applySpotlightToIframe(wnd);
  }
}

/**
 * Inject our decoration override layer + group-pairing observer + spotlight
 * stylesheet stub into a freshly-loaded EPUB iframe. Idempotent: flagged on
 * the iframe documentElement so repeated `frameLoaded` calls are no-ops.
 *
 * What this layer adds on top of upstream's Decorator:
 *   1. **Underline via DOM-fallback path**: CSS rule on
 *      `[data-group$="__underline"] .readium-highlight` swaps the filled box
 *      for a border-bottom in the tint colour. A MutationObserver mirrors
 *      each upstream-injected box's inline `background-color` to a CSS custom
 *      property the rule reads for the underline colour.
 *   2. **Underline via Web Highlight API path**: a head MutationObserver
 *      watches for upstream's `<style id="readium-decoration-N-style">`
 *      additions and inserts a sibling style whose `text-decoration: underline`
 *      rule wins by cascade order.
 *   3. **Spotlight stylesheet stub**: empty `<style>` slot ready to be filled
 *      by {@link setSpotlightGroupOnIframes}.
 *
 * (The `ruler` reading-mask is handled separately by {@link setRulerBandForGroup},
 * which positions dim overlays from the active range's geometry — it works
 * regardless of whether Readium renders via boxes or the CSS Custom Highlight
 * API, where no decoration box exists.)
 */
export function injectDecorationOverrides(wnd: Window): void {
  const doc = wnd.document;
  if (doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] === "true") return;
  doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] = "true";

  const overrides = doc.createElement("style");
  overrides.dataset.readium = "true";
  overrides.id = OVERRIDES_STYLE_ID;
  overrides.textContent = `
    [data-group$="${UNDERLINE_GROUP_SUFFIX}"] .readium-highlight {
      background-color: transparent !important;
      border-bottom: 0.15em solid var(--flutter-readium-underline-tint, currentColor) !important;
      box-sizing: border-box !important;
    }
  `;
  doc.head.appendChild(overrides);

  // ── Underline tint mirror (DOM-fallback path) ───────────────────────────
  const mirrorTint = (box: HTMLElement) => {
    const tint = box.style.backgroundColor;
    if (tint) {
      box.style.setProperty("--flutter-readium-underline-tint", tint);
    }
  };
  const isUnderlineBox = (el: HTMLElement): boolean =>
    el.classList?.contains("readium-highlight") === true &&
    el.closest(`[data-group$="${UNDERLINE_GROUP_SUFFIX}"]`) !== null;

  const bodyObserver = new MutationObserver((mutations) => {
    for (const m of mutations) {
      // Avoid Array.from(NodeList) — in Flutter web, dart2js patches Array.from
      // to use its own iterator protocol, which fails for raw DOM Node objects.
      for (let i = 0; i < m.addedNodes.length; i++) {
        const node = m.addedNodes[i];
        if (node.nodeType !== 1) continue;
        const el = node as HTMLElement;
        if (isUnderlineBox(el)) mirrorTint(el);
        el.querySelectorAll?.(
          `[data-group$="${UNDERLINE_GROUP_SUFFIX}"] .readium-highlight`
        ).forEach((b) => mirrorTint(b as HTMLElement));
      }
    }
  });
  bodyObserver.observe(doc.body, { childList: true, subtree: true });

  // ── Group pairing observer (Web Highlight API path + spotlight) ─────────
  const isReadiumGroupStyle = (el: Element): el is HTMLStyleElement =>
    el.tagName === "STYLE" &&
    typeof (el as HTMLStyleElement).id === "string" &&
    /^readium-decoration-\d+-style$/.test((el as HTMLStyleElement).id);

  // Pair any pre-existing styles (in case Decorator mounted before us).
  doc.head.querySelectorAll("style[data-readium]").forEach((el) => {
    if (isReadiumGroupStyle(el)) pairWithPendingGroup(wnd, el);
  });

  const headObserver = new MutationObserver((mutations) => {
    for (const m of mutations) {
      // Avoid Array.from(NodeList) — in Flutter web, dart2js patches Array.from
      // to use its own iterator protocol, which fails for raw DOM Node objects.
      for (let i = 0; i < m.addedNodes.length; i++) {
        const node = m.addedNodes[i];
        if (node.nodeType !== 1) continue;
        const el = node as Element;
        if (isReadiumGroupStyle(el)) pairWithPendingGroup(wnd, el);
      }
    }
  });
  headObserver.observe(doc.head, { childList: true });

  // Apply current spotlight groups (if any) to the freshly-loaded iframe.
  if (_spotlightGroups.size > 0) {
    const state = getIframeState(wnd);
    state.spotlightGroups = new Set(_spotlightGroups);
    applySpotlightToIframe(wnd);
  }

  // Re-draw the ruler reading-mask band (if any group is active).
  if (_rulerLocatorsByGroup.size > 0) {
    applyRulerBandToIframe(wnd);
  }
}

// ---------------------------------------------------------------------------
// Flutter Readium helper-script injection
// ---------------------------------------------------------------------------

/**
 * Dataset flag set on an iframe's documentElement once our helper scripts have
 * been injected, so repeated `frameLoaded` calls for the same frame are no-ops.
 */
const HELPER_INJECTED_FLAG = "flutterReadiumHelperInjected";

/**
 * Flutter web asset paths for the prebuilt helper bundle. These are the same
 * files that native (iOS / Android) injects into the EPUB webview, so injecting
 * them here gives the web iframe the same capabilities (comic pan/zoom overlay,
 * flutterReadium tools, responsive tables, etc.).
 */
const HELPER_JS_ASSET = "assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.js";
const HELPER_CSS_ASSET = "assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.css";

// Cache the fetched text so subsequent iframes (on the same page or after a
// chapter navigation) don't hit the network again.
let _cachedHelperJs: string | null = null;
let _cachedHelperCss: string | null = null;

async function _fetchHelperAssets(): Promise<{ js: string; css: string } | null> {
  try {
    if (_cachedHelperJs === null) {
      const res = await fetch(HELPER_JS_ASSET);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${HELPER_JS_ASSET}`);
      _cachedHelperJs = await res.text();
    }
    if (_cachedHelperCss === null) {
      const res = await fetch(HELPER_CSS_ASSET);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${HELPER_CSS_ASSET}`);
      _cachedHelperCss = await res.text();
    }
    return { js: _cachedHelperJs, css: _cachedHelperCss };
  } catch (err) {
    console.warn("[FlutterReadium] Failed to fetch helper assets:", err);
    return null;
  }
}

/**
 * Injects the Flutter Readium helper bundle (JS + CSS) and a bootstrap script
 * into a freshly-loaded EPUB iframe, mirroring what native iOS / Android do via
 * `WKUserScript` / `TransformingResource`.
 *
 * Injected in the same order as native:
 *   1. Bootstrap inline script: `isAndroid`, `isIos` flags + `window.readiumTocIDs`
 *   2. Helper CSS (as an inline `<style>`)
 *   3. Helper JS bundle (as an inline `<script>`)
 *
 * Idempotent: skipped when the iframe's `documentElement.dataset` already has
 * the `flutterReadiumHelperInjected` flag.
 *
 * @param wnd      The iframe's `contentWindow`.
 * @param tocIds   Flattened list of fragment ids from the publication's TOC.
 *                 Mirrors `window.readiumTocIDs` injected by native.
 */
export async function injectFlutterReadiumHelperScripts(
  wnd: Window,
  tocIds: string[]
): Promise<void> {
  const doc = wnd.document;

  if (doc.documentElement.dataset[HELPER_INJECTED_FLAG] === "true") return;
  doc.documentElement.dataset[HELPER_INJECTED_FLAG] = "true";

  const assets = await _fetchHelperAssets();
  if (!assets) return;

  // 1. Bootstrap: OS flags + TOC ids + null-guard for document.scrollingElement.
  //
  // The Readium ColumnSnapper calls `document.scrollingElement.scrollWidth`
  // unconditionally from a ResizeObserver and MutationObserver. In quirks-mode
  // documents (common in FXL/comic EPUBs), Chrome returns null from
  // `document.scrollingElement` whenever <body> is "potentially scrollable" (i.e.
  // has overflow:auto/scroll). Readium CSS injects those overflow values AFTER our
  // injection, so a conditional guard checked at injection time doesn't help —
  // the getter turns null later and the ResizeObserver fires into a crash.
  //
  // Fix: unconditionally shadow the prototype getter on this document instance
  // so it always returns <body> or <documentElement> instead of null. This is safe
  // for both quirks-mode (returns body, the intended scroll root) and standards-mode
  // (documentElement is the correct scroll root either way).
  const bootstrap = doc.createElement("script");
  bootstrap.textContent = [
    "const isAndroid = false;",
    "const isIos = false;",
    `window.readiumTocIDs = ${JSON.stringify(tocIds)};`,
    // Unconditional patch: shadow the scrollingElement getter on this document
    // instance so it never returns null (see comment above).
    "(function() {",
    "  try {",
    "    Object.defineProperty(document, 'scrollingElement', {",
    "      get: function() { return document.body || document.documentElement; },",
    "      configurable: true",
    "    });",
    "  } catch (_) {}",
    "})();",
  ].join("\n");
  doc.head.appendChild(bootstrap);

  // 2. CSS
  const style = doc.createElement("style");
  style.textContent = assets.css;
  doc.head.appendChild(style);

  // 3. JS bundle
  const script = doc.createElement("script");
  script.textContent = assets.js;
  doc.head.appendChild(script);
}

export function highlightSelection(
  nav: EpubNavigator | WebPubNavigator,
  publication: ReadiumPublication,
  selection: BasicTextSelection
) {
  // TODO: Save decoration state to re-apply after reload
  // Should probably be handled by the Flutter side
  // TODO:  Make optional and configurable decoration style
  // For now, hardcode a simple highlight style that always happens on textSelection
  const currentLocator = nav.currentLocator;
  const locator = new Locator({
    href: currentLocator.href,
    type: currentLocator.type,
    locations: currentLocator.locations,
    text: {
      highlight: selection.text,
    } as LocatorText,
  });

  const decorationId = [selection.text, selection.x, selection.y].join("_");

  const decoration = {
    id: decorationId,
    locator,
    style: {
      tint: "#ff9fff55",
      layout: Layout.Bounds,
      width: Width.Wrap,
    },
  };

  sendDecorate(nav, "selection_" + publication.metadata.identifier, "add", decoration);
}
