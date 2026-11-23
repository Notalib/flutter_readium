/**
 * Reading positions precise enough for the content iterator TTS reads from.
 *
 * The iterator starts mid-resource only at an element found by the locator's
 * `cssSelector`, which it runs against its own parse of the resource, not the
 * rendered frame. Selectors here therefore only rely on the element structure
 * the two share.
 */

import { Locator } from "@readium/shared";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("FirstVisible");

/**
 * Returns `current` with a `cssSelector` for the first block element visible in
 * one of `frameWindows`, or `current` unchanged when it already has one or
 * none can be found.
 *
 * The visual navigator's locator only carries a progression in the resource.
 * The content iterator ignores progression, so without this TTS starts at the
 * top of the chapter. iOS does the same lookup (`getFirstVisibleLocator`).
 */
export function withFirstVisibleElement(current: Locator, frameWindows: Window[]): Locator {
  // A fixed-layout spread shows two resources side by side, and a frame cannot
  // be matched to `current.href` (frames load from blob URLs), so TTS there
  // starts at the top of the page.
  if (frameWindows.length !== 1 || current.locations.otherLocations?.get("cssSelector")) return current;
  const wnd = frameWindows[0];
  try {
    const element = findFirstVisibleElement(wnd, wnd.document.body);
    if (!element) return current;
    // The iterator reads a progression of exactly 1 as "start at the end of
    // the resource" and then ignores the selector. The reader reports 1 on
    // the last page of a chapter, so the found element replaces it.
    const located = current.copyWithLocations({ progression: undefined });
    // Nothing before it means the top of the resource, which needs no
    // selector. The iterator also mis-starts on such an element: it records
    // its start index only while that is still 0, so a wrapper with nothing
    // before it starts after its first paragraph, or after its whole content.
    if (!hasContentBefore(element)) return located;
    const otherLocations = new Map(current.locations.otherLocations ?? []);
    otherLocations.set("cssSelector", bodyPathSelector(element));
    return located.copyWithLocations({ otherLocations });
  } catch (error) {
    // A frame that is being torn down throws on access.
    log.debug("first visible element lookup failed:", error);
    return current;
  }
}

/**
 * Makes a selector from the toolkit's own content iterator usable for starting
 * a new one.
 *
 * The iterator builds element selectors relative to the document, as
 * `:scope > <html step> > ...`. In `Document.querySelector`, `:scope` is the
 * `html` element, so the selector misses and TTS restarts at the top of the
 * resource. Replacing the first two steps with `:root` gives the intended
 * element. Only that first step, written as `:nth-child(1)` or `html`, is
 * rewritten, so selectors from other sources are kept.
 */
export function withQueryableCssSelector(locator: Locator): Locator {
  const selector = locator.locations.otherLocations?.get("cssSelector");
  if (typeof selector !== "string" || !TOOLKIT_SELECTOR_PREFIX.test(selector)) return locator;
  const otherLocations = new Map(locator.locations.otherLocations);
  otherLocations.set("cssSelector", selector.replace(TOOLKIT_SELECTOR_PREFIX, ":root"));
  return locator.copyWithLocations({ otherLocations });
}

const TOOLKIT_SELECTOR_PREFIX = /^:scope > (?::nth-child\(1\)|html)(?= |$)/;

// `Node.ELEMENT_NODE` and `Node.TEXT_NODE`; the `Node` global is missing in node tests.
const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

/**
 * Whether text or an image comes before `element` in its body, so the iterator
 * has something to skip.
 */
export function hasContentBefore(element: Element): boolean {
  for (let el: Element | null = element; el && el.tagName.toUpperCase() !== "BODY"; el = el.parentElement) {
    for (let node = el.previousSibling; node; node = node.previousSibling) {
      // Comments and processing instructions give the iterator nothing to read.
      if (node.nodeType !== ELEMENT_NODE && node.nodeType !== TEXT_NODE) continue;
      if (node.nodeName.toUpperCase() === "IMG" || node.textContent?.trim()) return true;
    }
  }
  return false;
}

/**
 * Tags the content iterator treats as blocks. It can only start at a block, so
 * a selector for an inline element would make TTS start at the top of the
 * resource instead. A block tag missing here is skipped in favor of its parent
 * or next sibling. `SUMMARY` is left out on purpose: the iterator treats it as
 * inline.
 */
const BLOCK_TAGS = new Set([
  "ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "CAPTION", "DD", "DETAILS", "DIV", "DL", "DT",
  "FIELDSET", "FIGCAPTION", "FIGURE", "FOOTER", "FORM", "H1", "H2", "H3", "H4", "H5", "H6",
  "HEADER", "HGROUP", "LI", "MAIN", "NAV", "OL", "P", "PRE", "SECTION", "TABLE",
  "TBODY", "TD", "TH", "THEAD", "TR", "UL",
]);

/**
 * First block element under `root` that is on screen, descending into blocks
 * that are only partly visible. A paragraph continued from the previous page
 * counts, like the injectables' own lookup, so no sentence on the page is
 * skipped.
 */
export function findFirstVisibleElement(wnd: Window, root: Element | null): Element | undefined {
  // Sibling links rather than iterating `children`: in a Flutter debug build,
  // iterating a content frame's collections from this realm throws.
  for (let child = root?.firstElementChild ?? null; child; child = child.nextElementSibling) {
    if (!BLOCK_TAGS.has(child.tagName.toUpperCase())) continue;
    const rect = child.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) continue;
    const visible =
      rect.right > 0 && rect.left < wnd.innerWidth && rect.bottom > 0 && rect.top < wnd.innerHeight;
    if (!visible) continue;
    const fullyVisible =
      rect.left >= 0 && rect.right <= wnd.innerWidth && rect.top >= 0 && rect.bottom <= wnd.innerHeight;
    if (fullyVisible) return child;
    return findFirstVisibleElement(wnd, child) ?? child;
  }
  return undefined;
}

/**
 * `body > :nth-child(i) > ...` down to `element`. Positions count from the
 * start, so elements the navigator appends to the rendered body do not shift
 * them.
 */
export function bodyPathSelector(element: Element): string {
  const steps: string[] = [];
  for (let el: Element | null = element; el && el.tagName.toUpperCase() !== "BODY"; el = el.parentElement) {
    let index = 1;
    for (let sibling = el.previousElementSibling; sibling; sibling = sibling.previousElementSibling) {
      index++;
    }
    steps.unshift(`:nth-child(${index})`);
  }
  return ["body", ...steps].join(" > ");
}
