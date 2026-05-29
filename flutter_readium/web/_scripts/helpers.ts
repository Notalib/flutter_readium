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
export const RULER_GROUP_SUFFIX = "__ruler";

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
  // The currently-active spotlight group (mirrors module state, kept for reapply)
  spotlightGroup: string | null;
}

let _currentSpotlightGroup: string | null = null;

function getIframeState(wnd: Window): IframeDecorationState {
  const w = wnd as any;
  if (!w[IFRAME_STATE_KEY]) {
    w[IFRAME_STATE_KEY] = {
      pendingNewGroups: [],
      groupInternalId: new Map<string, string>(),
      spotlightGroup: null,
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
 * Set or clear the spotlight group across the given iframes. When a group is
 * set, all body text in the iframe is dimmed and the spotlight group's
 * `::highlight()` pseudo-elements restore original color. Passing `null`
 * removes the dim and spotlight rules.
 *
 * Limitation: spotlight only takes effect when upstream uses the CSS Custom
 * Highlight API path (`"Highlight" in window`). In the DOM-fallback path the
 * `.readium-highlight` box sits *behind* dimmed text, so the dim still shows
 * through. Document this for callers.
 */
export function setSpotlightGroupOnIframes(
  iframes: Window[],
  group: string | null
): void {
  _currentSpotlightGroup = group;
  for (const wnd of iframes) {
    const state = getIframeState(wnd);
    state.spotlightGroup = group;
    applySpotlightToIframe(wnd);
  }
}

function applySpotlightToIframe(wnd: Window): void {
  const doc = wnd.document;
  const body = doc.body;
  if (!body) return;
  const state = getIframeState(wnd);
  const group = state.spotlightGroup;

  body.classList.toggle(SPOTLIGHT_CLASS, !!group);

  let styleEl = doc.getElementById(SPOTLIGHT_STYLE_ID) as HTMLStyleElement | null;
  if (!styleEl) {
    styleEl = doc.createElement("style");
    styleEl.id = SPOTLIGHT_STYLE_ID;
    styleEl.dataset.readium = "true";
    doc.head.appendChild(styleEl);
  }
  if (!group) {
    styleEl.textContent = "";
    return;
  }
  const internalIds: string[] = [];
  const mainId = state.groupInternalId.get(group);
  if (mainId) internalIds.push(mainId);
  const underlineId = state.groupInternalId.get(group + UNDERLINE_GROUP_SUFFIX);
  if (underlineId) internalIds.push(underlineId);

  const restoreRules = internalIds
    .map(
      (id) =>
        `body.${SPOTLIGHT_CLASS} ::highlight(${id}) { color: initial !important; }`
    )
    .join("\n  ");

  styleEl.textContent = `
    body.${SPOTLIGHT_CLASS},
    body.${SPOTLIGHT_CLASS} * {
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
  if (state.spotlightGroup) {
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

  // Apply current spotlight (if any) to the freshly-loaded iframe.
  if (_currentSpotlightGroup) {
    const state = getIframeState(wnd);
    state.spotlightGroup = _currentSpotlightGroup;
    applySpotlightToIframe(wnd);
  }
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
