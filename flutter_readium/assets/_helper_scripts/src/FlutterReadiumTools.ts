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
