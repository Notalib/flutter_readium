import { initResponsiveTables } from './Tables';
import { PageInformation } from './types';
import { NotaComicBook } from './NotaComicBookPage';
import { getCssSelector } from "css-selector-generator";
import './FlutterReadiumTools.scss';

class FlutterReadiumTools {
  get #isScrollModeEnabled(): boolean {
    return window.readium?.isReflowable === true && getComputedStyle(document.documentElement).getPropertyValue('--USER__view')?.trim() === 'readium-scroll-on"';
  }

  /**
   * List of all ids from the publication's Table of Contents, in lowercase for easier comparison.
   * This is used to find the nearest ToC element to the current reading position.
   */
  #tocIds: string[] = [];

  /**
   * Register all the ToC ids for the publication. Should be called in the EpubNavigator's onPageLoaded() callback.
   */
  public registerToc(ids: string[]) {
    ids.forEach((id) => {
      const lowerCaseId = id.toLocaleLowerCase();
      if (this.#tocIds.includes(lowerCaseId)) {
        return;
      }

      const elementId = document.getElementById(id)?.id?.toLocaleLowerCase();
      if (elementId) {
        this.#tocIds.push(lowerCaseId);
      }
    });
  }

  public getViewPortSize(): { width: number; height: number, scrollTop: number, scrollLeft: number, scrollHeight: number, scrollWidth: number } {
    const scrollingElement = document.scrollingElement ?? document.documentElement;

    return {
      width: Math.ceil(scrollingElement.clientWidth),
      height: Math.ceil(scrollingElement.clientHeight),
      scrollTop: Math.ceil(scrollingElement.scrollTop),
      scrollLeft: Math.ceil(scrollingElement.scrollLeft),
      scrollHeight: Math.floor(scrollingElement.scrollHeight),
      scrollWidth: Math.floor(scrollingElement.scrollWidth),
    };
  }

  /**
   * Find current page information, including physical page, css selector of the current position, and the nearest ToC element id.
   */
  public getPageInformation(): PageInformation {
    if (window.readiumTocIDs) {
      this.registerToc(window.readiumTocIDs);
      delete window.readiumTocIDs;
    }

    const physicalPage = this.#findCurrentPhysicalPage();
    const cssSelector = this.#findCssSelector();
    const tocId = this.#findTocId(cssSelector);
    const { currentPage, totalPages } = this.#findResourcePagination();

    return {
      physicalPage,
      cssSelector,
      tocId,
      currentPage,
      totalPages,
    };
  }

  /**
   * Compute the current page index and total page count within the current resource.
   *
   * Only meaningful in paginated (horizontal) layouts. In scroll mode there is no
   * page concept, so both values are returned as `null`.
   */
  #findResourcePagination(): { currentPage: number | null; totalPages: number | null } {
    if (this.#isScrollModeEnabled) {
      return { currentPage: null, totalPages: null };
    }

    const scrollingElement = document.scrollingElement ?? document.documentElement;
    const width = scrollingElement.clientWidth;
    const scrollWidth = scrollingElement.scrollWidth;
    if (width <= 0 || scrollWidth <= 0) {
      return { currentPage: null, totalPages: null };
    }

    const totalPages = Math.max(1, Math.round(scrollWidth / width));
    const currentPage = Math.min(totalPages, Math.floor(scrollingElement.scrollLeft / width) + 1);

    return { currentPage, totalPages };
  }

  public setSegmentDuration(duration: number) {
    if (window.comicBookPage) {
      window.comicBookPage.segmentDuration = duration;
    }
  }

  /**
   * Find the nearest cssSelector that is an id.
   *
   * @param cssSelector
   * @returns cssSelector that is guaranteed to be an id, or undefined if no element can be found.
   */
  #findCssSelector(): string | undefined {
    let cssSelector = window.readium?.findFirstVisibleLocator()?.locations?.cssSelector ?? null;
    if (!cssSelector) {
      return;
    }

    const element = document.querySelector<HTMLElement>(cssSelector);
    if (element == null) {
      return;
    }

    if (element.nodeType !== Node.ELEMENT_NODE || this.#isPageBreakElement(element)) {
      // Make sure the cssSelector isn't inside a page break element or a text-node.
      if (element.parentElement) {
        cssSelector = getCssSelector(element.parentElement);
      }
    }

    return cssSelector;
  }

  /**
   * Find the nearest Table of Content's element id.
   * If a ToC element is visible, we return it. Otherwise we look for the nearest preceding ToC element to the current reading position.
   *
   * @param cssSelector The current cssSelector or current reading position. This is used to find the nearest ToC element if there is no visible ToC element.
   * @returns The id of the nearest ToC element, or null if none is found.
   */
  #findTocId(cssSelector: string | undefined): string | undefined {
    const tocIds = [...this.#tocIds];
    if (tocIds.length === 0) {
      console.warn("No ToC ids registered. Fallback to finding all heading elements as ToC candidates.");

      document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((element) => {
        if (element.id) {
          tocIds.push(element.id.toLocaleLowerCase());
        }
      });
    }

    // First we check if a ToC element is visible. If yes, we return it immediately.
    for (const tocId of tocIds) {
      const tocElement = document.getElementById(tocId);
      if (this.#isElementVisible(tocElement)) {
        return tocId;
      }
    }

    if (!cssSelector) {
      console.warn("cssSelector is null. Cannot find ToC element.");
      return;
    }

    // Since there wasn't a visible ToC element, we need to find the nearest one to the current reading position.
    const cssSelectorElement = document.querySelector(cssSelector);
    if (cssSelectorElement == null) {
      return;
    }

    // If the current cssSelector element is a ToC element, return it's id immediately.
    if (cssSelectorElement.id && tocIds.includes(cssSelectorElement.id.toLocaleLowerCase())) {
      return cssSelectorElement.id;
    }

    if (tocIds.length !== 0) {
      // Now look backwards from the cssSelector to find the nearest preceding ToC element.
      const predicate = tocIds.map((id) => `@id="${id}"`).join(" or ");

      const precedingElementXPath = `preceding::*[${predicate}][1]`;
      const result = document.evaluate(
        precedingElementXPath,
        cssSelectorElement,
        null,
        XPathResult.FIRST_ORDERED_NODE_TYPE,
        null
      );

      // We found one, return it.
      if (result.singleNodeValue instanceof Element && result.singleNodeValue.id) {
        return result.singleNodeValue.id
      }
    }

    // This might be a special case, where we start just before the first ToC element.
    let firstTocElement: Element | null = null;
    for (const tocId of tocIds) {
      const tocElement = document.getElementById(tocId);
      if (tocElement) {
        firstTocElement = tocElement;
        break;
      }
    }

    if (firstTocElement == null) {
      // Really shouldn't happen.
      return;
    }

    // Sometimes the cssSelector lands before the first ToC element.
    // In this case; We need to walk backwards from the first ToC element and if we find the current cssSelector,
    // we know the first ToC element is the current ToC element.
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = firstTocElement;
    for (let node: Node | null = firstTocElement; node; node = walker.previousNode()) {
      if (node instanceof HTMLElement && node === cssSelectorElement && firstTocElement.id) {
        // First ToC element is the current one.
        return firstTocElement.id;
      }
    }
  }

  /**
   * Is the given element a page break element, based on EPUB specification or common practices?
   *
   * @param element
   * @returns
   */
  #isPageBreakElement(element: HTMLElement | null): boolean {
    if (element == null) {
      return false;
    }

    return element.getAttributeNS("http://www.idpf.org/2007/ops", "type") === 'pagebreak' || element.getAttribute('type') === 'pagebreak' || element.getAttribute('epub:type') === 'pagebreak';
  }

  /**
   * Get the physical page text from the given element, if it is a page break element.
   *
   * @param element The element to get the physical page text from.
   * @returns The physical page text, or undefined if the element is not a page break element.
   */
  #getPhysicalPageText(element: HTMLElement): string | undefined {
    if (!this.#isPageBreakElement(element)) {
      return;
    }

    return element?.getAttribute('title') ?? element?.innerText.trim();
  }

  /**
   * Find the current physical page index.
   *
   * @returns The physical page index, or null if it cannot be determined.
   */
  #findCurrentPhysicalPage(): string | undefined {
    let element = this.#findFirstVisibleElement();
    if (!(element instanceof HTMLElement)) {
      return;
    }

    if (this.#isPageBreakElement(element)) {
      return this.#getPhysicalPageText(element);
    }

    const result = document.evaluate(
      'preceding::*[@epub:type="pagebreak" or @type="pagebreak" or @role="doc-pagebreak" or contains(@class,"pagebreak")][1]',
      element,
      (prefix: string | null) => {
        if (prefix === "epub") {
          return "http://www.idpf.org/2007/ops";
        }
        return null;
      },
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    );

    if (result.singleNodeValue instanceof HTMLElement && this.#isPageBreakElement(result.singleNodeValue)) {
      return this.#getPhysicalPageText(result.singleNodeValue);
    }
  }

  /**
   * Find the first visible element in the document.
   * @returns The first visible element, or null if none is found.
   */
  #findFirstVisibleElement(): HTMLElement | undefined {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = document.body.firstElementChild ?? document.body;

    for (let node: Node | null = walker.currentNode; node; node = walker.nextNode()) {
      if (node instanceof HTMLElement && this.#isElementVisible(node)) {
        return node;
      }
    }

    return;
  }

  // Functions below was copied from Swift-toolkit - see License.readium-swift-toolkit for details.
  #isElementVisible(element: Element | null): boolean {
    if (element == null) {
      return false;
    }

    if (this.#shouldIgnoreElement(element)) {
      return false;
    }

    if (window.readium?.isFixedLayout) return true;

    if (element === document.body || element === document.documentElement) {
      return true;
    }

    if (!document || !document.documentElement || !document.body) {
      return false;
    }

    const rect = element.getBoundingClientRect();
    if (this.#isScrollModeEnabled) {
      return rect.bottom > 0 && rect.top < window.innerHeight;
    } else {
      return rect.right > 0 && rect.left < window.innerWidth;
    }
  }

  #shouldIgnoreElement(element: Element | null): boolean {
    if (element == null) {
      return true;
    }

    const elStyle = getComputedStyle(element);
    if (elStyle) {
      const display = elStyle.getPropertyValue("display");
      if (display != "block") {
        return true;
      }
      // Cannot be relied upon, because web browser engine reports invisible when out of view in
      // scrolled columns!
      // const visibility = elStyle.getPropertyValue("visibility");
      // if (visibility === "hidden") {
      //     return false;
      // }
      const opacity = elStyle.getPropertyValue("opacity");
      if (opacity === "0") {
        return true;
      }
    }

    return false;
  }
}

declare global {
  interface Window {
    flutterReadium: FlutterReadiumTools;
    readiumTocIDs?: string[];

    isNotaComicBook: () => boolean;
    comicBookPage?: NotaComicBook;
    gotoComicFrame: (id: string, duration: number) => void;
    debugCaptureReadiumFunctionCalls: () => void;
  }
}


function Setup() {
  if (window.flutterReadium) {
    return;
  }

  document.removeEventListener('DOMContentLoaded', Setup);
  try {
    // Copy the custom css variables from style-elment to the root element's style property.
    // This is needed for the CSS selectors to work correctly.
    const styles = getComputedStyle(document.documentElement)
    for (let i = 0; i < styles.length; i += 1) {
      const key = styles[i];
      if (key.startsWith('--FLUTTER_READIUM')) {
        const value = styles.getPropertyValue(key);

        // We can't reliably use the readium.setCSSProperties at this time. Use the DOM function directly.
        document.documentElement.style.setProperty(key, value, 'important');
      }
    }
  } catch (e) {
    console.warn("Failed to copy CSS variables to root element. This might cause some styles to not work correctly.", e);
  }

  // Create the tools in an animation frame to prevent it from blocking the webview initial rendering.
  requestAnimationFrame(() => {
    window.flutterReadium = new FlutterReadiumTools();

    if (window.isNotaComicBook()) {
      window.comicBookPage = new NotaComicBook();
    }

    initResponsiveTables();
    startSpotlightObserver(document);
  });
}

if (document.readyState !== 'loading') {
  window.setTimeout(Setup);
} else {
  document.addEventListener('DOMContentLoaded', Setup);
}

window.gotoComicFrame = (id: string, duration: number) => {
  if (window.comicBookPage) {
    window.comicBookPage.gotoComicFrame(id, duration);
  } else {
    console.warn("gotoComicFrame: Comic book page is not available.");
  }
}

/**
 * Watch for `.flutter-readium-spotlight` decoration elements being added or
 * removed from the document.
 *
 * On activation, two paths are tried in order:
 *
 * 1. **CSS Custom Highlight API** (iOS 17.2+, Chrome 105+): reads
 *    `data-text-highlight` / `data-text-before` from the decoration element,
 *    walks the text nodes of the containing element to locate the exact spoken
 *    range, and registers it as `CSS.highlights.set('flutter-readium-spotlit', …)`.
 *    A `::highlight()` rule in FlutterReadiumTools.scss restores the text colour
 *    for precisely those characters, leaving the rest of the paragraph dimmed.
 *
 * 2. **Class fallback** (all other platforms): adds `.flutter-readium-spotlit-text`
 *    to the containing element. A higher-specificity CSS rule restores colour at
 *    element granularity (whole paragraph un-dimmed rather than exact range).
 *
 * In both cases `body.flutter-readium-spotlight-active` gates the body-wide
 * text-fade rule that dims everything except the spotlit range.
 *
 * On deactivation, both the `CSS.highlights` entry and any class marks are cleared.
 */
function startSpotlightObserver(doc: Document): void {
  const SPOTLIGHT_ELEM_CLASS = 'flutter-readium-spotlight';
  const BODY_ACTIVE_CLASS    = 'flutter-readium-spotlight-active';
  const SPOTLIT_TEXT_CLASS   = 'flutter-readium-spotlit-text';
  const HIGHLIGHT_KEY        = 'flutter-readium-spotlit';
  // CSS custom property written to body.style so ::highlight() can use the
  // same tint colour as the decoration div without hard-coding yellow.
  const TINT_VAR             = '--flutter-readium-spotlight-tint';

  // Detect CSS Custom Highlight API once at setup — stable for the page lifetime.
  const highlightRegistry = (typeof CSS !== 'undefined')
    ? (CSS as unknown as Record<string, unknown>).highlights as
        { set(k: string, v: unknown): void; delete(k: string): void } | undefined
    : undefined;
  const HighlightCtor = (window as unknown as Record<string, unknown>).Highlight as
    (new (...ranges: Range[]) => unknown) | undefined;
  const supportsHighlightApi = !!(highlightRegistry && HighlightCtor);
  if (!supportsHighlightApi) {
    console.warn('[spotlight] CSS Custom Highlight API not supported in this browser. Falling back to class-based spotlight with reduced precision and potential edge-case bugs.');
  }

  const update = () => {
    const spotlightElems = doc.querySelectorAll('.' + SPOTLIGHT_ELEM_CLASS);
    const isActive = spotlightElems.length > 0;

    doc.body.classList.toggle(BODY_ACTIVE_CLASS, isActive);

    // Clear both paths from the previous tick.
    if (supportsHighlightApi) highlightRegistry!.delete(HIGHLIGHT_KEY);
    doc.querySelectorAll('.' + SPOTLIT_TEXT_CLASS).forEach((el) => {
      el.classList.remove(SPOTLIT_TEXT_CLASS);
    });
    doc.body.style.removeProperty(TINT_VAR);

    if (!isActive) return;

    spotlightElems.forEach((spotlightElem) => {
      const cssSelector = spotlightElem.getAttribute('data-css-selector');
      if (!cssSelector) return;

      let target: Element | null = null;
      try { target = doc.querySelector(cssSelector); } catch { return; }
      if (!target) return;

      // Path 1 — CSS Custom Highlight API: sub-element precision.
      if (supportsHighlightApi) {
        const textHighlight = spotlightElem.getAttribute('data-text-highlight');
        const textBefore    = spotlightElem.getAttribute('data-text-before') ?? '';
        if (textHighlight) {
          const range = findTextRange(target, textBefore, textHighlight);
          if (range) {
            highlightRegistry!.set(HIGHLIGHT_KEY, new HighlightCtor!(range));
            // Forward the tint colour to ::highlight() via a CSS variable.
            // Read it from the data-tint attribute set by native — a plain CSS
            // colour string (e.g. "rgba(253,255,0,0.5)") or "transparent".
            // Using the attribute is reliable regardless of ReadiumCSS overrides,
            // whereas getComputedStyle would return the ReadiumCSS-forced
            // transparent value and lose the native-configured colour.
            const tint = spotlightElem.getAttribute('data-tint') || 'transparent';
            doc.body.style.setProperty(TINT_VAR, tint);
            // Strip the decoration div's own background. The native template
            // sets `background-color: … !important` as an inline style, which
            // cannot be overridden by any stylesheet rule (inline !important
            // beats author !important regardless of specificity). Removing it
            // directly from the element's style object lets ReadiumCSS keep
            // the div transparent, leaving ::highlight() as the sole visual
            // highlight on the precise spoken range.
            (spotlightElem as HTMLElement).style.removeProperty('background-color');
            console.debug('[spotlight] Path 1 (Highlight API): precise range registered.');
            return; // Precise range registered — no class fallback needed.
          }
          console.warn('[spotlight] Path 1 failed: text not found in element, falling back to class.', { cssSelector: spotlightElem.getAttribute('data-css-selector'), textHighlight });
        } else {
          console.warn('[spotlight] Path 1 skipped: data-text-highlight is empty, falling back to class.');
        }
      }

      // Path 2 — class fallback: element-level granularity.
      console.debug('[spotlight] Path 2 (class fallback): marking element', target);
      target.classList.add(SPOTLIT_TEXT_CLASS);
    });
  };

  new MutationObserver(update).observe(doc.body, { childList: true, subtree: true });
}

/**
 * Walk the text nodes inside `element` and return a Range covering the first
 * occurrence of `textHighlight`, anchored by `textBefore` to disambiguate when
 * the same text appears more than once.
 *
 * Returns null if the text cannot be located (e.g. whitespace normalisation
 * differences between the TTS locator and the DOM) — callers should fall back
 * to the class-based approach in that case.
 */
function findTextRange(
  element: Element,
  textBefore: string,
  textHighlight: string,
): Range | null {
  if (!textHighlight) return null;

  // Collect all text nodes within the element and build a flat string.
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  const nodeOffsets: { node: Text; start: number }[] = [];
  let fullText = '';
  let node: Node | null;
  while ((node = walker.nextNode())) {
    nodeOffsets.push({ node: node as Text, start: fullText.length });
    fullText += (node as Text).textContent ?? '';
  }
  if (nodeOffsets.length === 0) return null;

  // Use the tail of textBefore (last 80 chars) to locate the search start.
  // This avoids mismatches caused by whitespace differences earlier in the text.
  let searchFrom = 0;
  if (textBefore) {
    const beforeTail = textBefore.slice(-80);
    const contextIdx = fullText.indexOf(beforeTail);
    if (contextIdx !== -1) searchFrom = contextIdx + beforeTail.length;
  }

  const hlStart = fullText.indexOf(textHighlight, searchFrom);
  if (hlStart === -1) return null;
  const hlEnd = hlStart + textHighlight.length;

  // Map a flat text offset back to (textNode, node-local offset).
  const resolve = (pos: number): { node: Text; offset: number } | null => {
    for (let i = nodeOffsets.length - 1; i >= 0; i--) {
      if (nodeOffsets[i].start <= pos) {
        return { node: nodeOffsets[i].node, offset: pos - nodeOffsets[i].start };
      }
    }
    return null;
  };

  const start = resolve(hlStart);
  const end   = resolve(hlEnd);
  if (!start || !end) return null;

  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset);
  return range;
}

let hasCapturedReadiumFunctions = false;

window.debugCaptureReadiumFunctionCalls = () => {
  if (hasCapturedReadiumFunctions) {
    return;
  }

  hasCapturedReadiumFunctions = true;

  if (typeof window.readium !== 'undefined') {
    const readium = window.readium;
    const readiumProxy = readium as unknown as Record<string, unknown>;

    Object.keys(readiumProxy).forEach((key) => {
      if (key === 'scrollToId') {
        return;
      }

      const originalFn = readiumProxy[key] as (...args: any[]) => unknown;
      console.log(`Checking readium function: ${key}`, originalFn);
      if (typeof originalFn === 'function') {
        // Proxy other readium functions to preserve original functionality, except for scrollToId which we override to handle comic frame scrolling.
        readiumProxy[key] = (...args: any[]) => {
          console.log(`Calling readium function: ${key} with arguments:`, args);
          return originalFn.apply(readium, args);
        };
      }
    });
  }
}
