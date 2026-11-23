import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("DecorationFrames");

/**
 * Group-name suffix used to mark a decoration group as a "spotlight" group.
 * While any spotlight group is active, all body text is dimmed. The spotlit
 * range stays readable because the toolkit's own `::highlight()` rule sets its
 * text colour.
 */
export const SPOTLIGHT_GROUP_SUFFIX = "__spotlight";

const OVERRIDES_DATASET_FLAG = "flutterReadiumOverrides";
const IFRAME_STATE_KEY = "__flutterReadiumDecorationState";
const SPOTLIGHT_CLASS = "flutter-readium-spotlight";
const SPOTLIGHT_STYLE_ID = "flutter-readium-spotlight-style";

interface IframeDecorationState {
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
    w[IFRAME_STATE_KEY] = { spotlightGroups: new Set<string>() } as IframeDecorationState;
  }
  return w[IFRAME_STATE_KEY];
}

/**
 * Return the list of content-frame `Window`s for a navigator. Used for fanning
 * out CSS injection to every loaded EPUB iframe.
 *
 * Skips frames whose iframe is already detached: upstream's `window` getter throws
 * for those, and teardown (e.g. TTS clearing its decorations on close) still runs here.
 */
export function navIframeWindows(
  nav: EpubNavigator | WebPubNavigator
): Window[] {
  const cframes: any[] = (nav as any)._cframes ?? [];
  const windows: Window[] = [];
  for (const f of cframes) {
    try {
      if (f?.window) windows.push(f.window);
    } catch (err) {
      log.debug("Skipping detached frame:", err);
    }
  }
  return windows;
}

/**
 * Clear all module-level spotlight state. Call on publication close so the
 * stale set does not re-apply the dim to the next publication's iframes when
 * `injectDecorationOverrides` fires on them.
 */
export function clearSpotlightState(): void {
  _spotlightGroups.clear();
}

/**
 * Activate or deactivate spotlight for a *single* group across the given
 * iframes. While any group is active, all body text is dimmed. Each group
 * toggles only its own contribution, so e.g. clearing `tts_range` never removes
 * a spotlight set by `tts_utterance`.
 *
 * Limitation: spotlight only takes effect when upstream uses the CSS Custom
 * Highlight API path (`"Highlight" in window`). In the DOM-fallback path the
 * `.readium-highlight` box sits *behind* dimmed text, so the dim still shows
 * through.
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
  // The spotlit range is not dimmed: the toolkit's `::highlight()` rule sets its own
  // `color`, and pseudo-element styles are cascaded separately from the `!important`
  // below. The fill is controlled by the spotlight decoration's tint: a non-transparent
  // tint fills the range, a transparent one gives pure dim-outside-only.
  //
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
  `;
}

/**
 * Re-apply any active spotlight to a freshly-loaded EPUB iframe.
 * Idempotent: flagged on the iframe documentElement so repeated `frameLoaded`
 * calls are no-ops.
 */
export function injectDecorationOverrides(wnd: Window): void {
  const doc = wnd.document;
  if (doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] === "true") return;
  doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] = "true";

  if (_spotlightGroups.size > 0) {
    const state = getIframeState(wnd);
    state.spotlightGroups = new Set(_spotlightGroups);
    applySpotlightToIframe(wnd);
  }
}
