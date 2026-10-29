/**
 * Shared helpers used by both FlutterEpubNavigator and FlutterWebPubNavigator.
 */

import { BasicTextSelection } from "@readium/navigator-html-injectables";
import { Locator, LocatorText } from "@readium/shared";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("NavUtils");

/**
 * Scrolls all visible Readium iframe content windows by 100px in the given
 * direction. Called by the Peripherals `moveTo` handler for keyboard up/down.
 */
export function scrollVisibleIframes(direction: "up" | "down"): void {
  const delta = direction === "up" ? -100 : 100;
  document.querySelectorAll(".readium-navigator-iframe").forEach((iframe) => {
    if (
      iframe instanceof HTMLIFrameElement &&
      iframe.style.visibility !== "hidden"
    ) {
      iframe.contentWindow?.scrollBy(0, delta);
    }
  });
}

/**
 * Handles an external-protocol locator href by prompting the user before
 * opening it in a new tab. For unrecognised hrefs (internal links that fell
 * through), logs a warning.
 */
export function handleExternalLocator(href: string): void {
  if (
    href.startsWith("http://") ||
    href.startsWith("https://") ||
    href.startsWith("mailto:") ||
    href.startsWith("tel:")
  ) {
    if (confirm(`Open "${href}" ?`)) window.open(href, "_blank");
  } else {
    log.warn("Unhandled locator href:", href);
  }
}

/** Content frame a text selection came from. */
export interface SelectionFrame {
  window: Window;
  iframe: HTMLIFrameElement;
}

/** What a navigator tells the reader about selections and view changes. */
export interface SelectionHooks {
  onTextSelected: (
    selection: BasicTextSelection,
    locator: Locator,
    frame: SelectionFrame | undefined
  ) => void;
  /** The visible page or position changed; any selection UI is stale. */
  onViewChanged: () => void;
}

// Enough surrounding text for the quote anchoring in the injectable to pick the
// right occurrence of a common word, without bloating persisted locators.
const SELECTION_CONTEXT_CHARS = 64;

/**
 * Finds the content frame whose document reported the selection
 * (`targetFrameSrc` is that document's `location.href`).
 */
export function findSelectionFrame(
  nav: { _cframes: ReadonlyArray<{ window: Window; iframe: HTMLIFrameElement } | undefined> },
  targetFrameSrc: string | undefined
): SelectionFrame | undefined {
  if (!targetFrameSrc) return undefined;
  for (const frame of nav._cframes) {
    try {
      if (frame && frame.window.location.href === targetFrameSrc) {
        return { window: frame.window, iframe: frame.iframe };
      }
    } catch {
      // A destroyed frame throws on access; it can't be the source.
    }
  }
  return undefined;
}

/**
 * Text before and after the current selection in `wnd`, measured over the
 * document's raw text nodes. That is the string the injectable's quote anchor
 * matches `before` / `after` against, so whitespace is deliberately not
 * normalised.
 */
function readSelectionContext(wnd: Window): { before: string; after: string } | undefined {
  const selection = wnd.getSelection();
  const body = wnd.document.body;
  if (!selection || selection.rangeCount === 0 || !body) return undefined;
  const range = selection.getRangeAt(0);

  const beforeRange = wnd.document.createRange();
  beforeRange.setStart(body, 0);
  beforeRange.setEnd(range.startContainer, range.startOffset);
  const afterRange = wnd.document.createRange();
  afterRange.setStart(range.endContainer, range.endOffset);
  afterRange.setEnd(body, body.childNodes.length);

  return {
    before: beforeRange.toString().slice(-SELECTION_CONTEXT_CHARS),
    after: afterRange.toString().slice(0, SELECTION_CONTEXT_CHARS),
  };
}

/**
 * Builds a locator for the selected text itself. The href comes from the frame
 * that reported the selection (a spread has two), and `before` / `after` let a
 * decoration made from this locator land on the selected occurrence rather than
 * the first match of the text in the chapter.
 */
export function buildSelectionLocator(
  currentLocator: Locator,
  selection: BasicTextSelection,
  frameWindow?: Window
): Locator {
  const href = selection.locator?.href ?? currentLocator.href;
  // Progression and position describe the current page, not another page of a spread.
  const sameResource = href === currentLocator.href;
  const context = frameWindow ? readSelectionContext(frameWindow) : undefined;
  return new Locator({
    href,
    type: selection.locator?.type ?? currentLocator.type,
    title: sameResource ? currentLocator.title : undefined,
    locations: sameResource ? currentLocator.locations : undefined,
    text: new LocatorText({
      highlight: selection.text,
      before: context?.before,
      after: context?.after,
    }),
  });
}

/** JSON payload for `window.onTextSelectedCallback` (Dart `TextSelectionEvent`). */
export function buildTextSelectionPayload(locator: Locator, selectedText: string): string {
  return JSON.stringify({ locator: locator.serialize(), selectedText });
}
