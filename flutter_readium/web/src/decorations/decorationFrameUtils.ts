import { EpubNavigator, WebPubNavigator } from "@readium/navigator";

/**
 * Group-name suffix used to mark a decoration group as a "spotlight" group.
 * While any spotlight group is active, all body text is dimmed and each active
 * group's `::highlight()` range restores its original colour, focusing the
 * reader on the spotlit range.
 */
export const SPOTLIGHT_GROUP_SUFFIX = "__spotlight";

const OVERRIDES_DATASET_FLAG = "flutterReadiumOverrides";
const IFRAME_STATE_KEY = "__flutterReadiumDecorationState";
const SPOTLIGHT_CLASS = "flutter-readium-spotlight";
const SPOTLIGHT_STYLE_ID = "flutter-readium-spotlight-style";

const GROUP_STYLE_ID = /^readium-decoration-\d+-style$/;

interface IframeDecorationState {
  // Ids of upstream group <style> elements already seen (paired or not), so each is paired once.
  seenStyleIds: Set<string>;
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
      seenStyleIds: new Set<string>(),
      groupInternalId: new Map<string, string>(),
      spotlightGroups: new Set<string>(),
    } as IframeDecorationState;
  }
  return w[IFRAME_STATE_KEY];
}

/**
 * Return the list of content-frame `Window`s for a navigator. Used for fanning
 * out CSS injection to every loaded EPUB iframe.
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
 * Clear all module-level spotlight state. Call on publication close so the
 * stale set does not re-apply the dim to the next publication's iframes when
 * `injectDecorationOverrides` fires on them.
 */
export function clearSpotlightState(): void {
  _spotlightGroups.clear();
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
  // Collect the upstream internal ids of every active spotlight group so each
  // gets its colour restored.
  const internalIds: string[] = [];
  for (const group of groups) {
    const id = state.groupInternalId.get(group);
    if (id) internalIds.push(id);
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
 * Pair each newly created upstream `<style id="readium-decoration-N-style">`
 * with the group of the `decorate` message that created it, so spotlight rules
 * can target that group's `::highlight()`.
 *
 * Upstream creates a group's style element synchronously while handling that
 * group's first successful `add`. This runs from a `message` listener that is
 * registered after upstream's, so by now upstream has handled `req`. Any style
 * we have not seen yet was therefore created by `req.group`. Because it only
 * reads the wire message, it needs no knowledge of the order in which
 * upstream numbers its groups.
 */
function pairNewGroupStyles(wnd: Window, message: unknown): void {
  const msg = message as { key?: unknown; data?: any } | null;
  if (!msg || typeof msg !== "object" || msg.key !== "decorate") return;
  const group = msg.data?.group;
  if (typeof group !== "string") return;

  const state = getIframeState(wnd);
  const styles = wnd.document.head.querySelectorAll<HTMLStyleElement>("style[id]");
  let paired = false;
  styles.forEach((styleEl) => {
    if (!GROUP_STYLE_ID.test(styleEl.id) || state.seenStyleIds.has(styleEl.id)) return;
    state.seenStyleIds.add(styleEl.id);
    const internalId = styleEl.id.replace(/-style$/, "");
    state.groupInternalId.set(group, internalId);
    paired = true;
  });

  // Spotlight rules may need to expand now that we know this group's internal id.
  if (paired && state.spotlightGroups.size > 0) {
    applySpotlightToIframe(wnd);
  }
}

/**
 * Install the group-pairing listener (see {@link pairNewGroupStyles}) in a
 * freshly-loaded EPUB iframe and apply any active spotlight. Idempotent: flagged
 * on the iframe documentElement so repeated `frameLoaded` calls are no-ops.
 */
export function injectDecorationOverrides(wnd: Window): void {
  const doc = wnd.document;
  if (doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] === "true") return;
  doc.documentElement.dataset[OVERRIDES_DATASET_FLAG] = "true";

  // Styles that already exist were created before we could see which group
  // asked for them, so they stay unpaired rather than risk a wrong pairing.
  const state = getIframeState(wnd);
  doc.head.querySelectorAll("style[id]").forEach((el) => {
    if (GROUP_STYLE_ID.test(el.id)) state.seenStyleIds.add(el.id);
  });
  wnd.addEventListener("message", (event: MessageEvent) => pairNewGroupStyles(wnd, event.data));

  // Apply current spotlight groups (if any) to the freshly-loaded iframe.
  if (_spotlightGroups.size > 0) {
    state.spotlightGroups = new Set(_spotlightGroups);
    applySpotlightToIframe(wnd);
  }
}

