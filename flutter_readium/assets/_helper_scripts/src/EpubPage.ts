import { initResponsiveTables } from './Tables';

import { PageInformation, Readium } from 'types';
import './EpubPage.scss';

declare const readium: Readium;

export class EpubPage {
  get #isScrollModeEnabled(): boolean {
    return readium.isReflowable === true && getComputedStyle(document.documentElement).getPropertyValue('--USER__view')?.trim() === 'readium-scroll-on"';
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
    this.#tocIds = this.#tocIds.concat(ids.map((id) => document.getElementById(id)?.id?.toLocaleLowerCase()).filter((id): id is string => id != null));
    console.error(`Registered ToC ids: ${this.#tocIds.join(", ")}`);
  }

  /**
   * Find current page information, including physical page, css selector of the current position, and the nearest ToC element id.
   */
  public getPageInformation(): PageInformation {
    const physicalPage = this.#findCurrentPhysicalPage();
    const cssSelector = this.#findCssSelector();
    const tocSelector = this.#findTocId(cssSelector);

    return {
      physicalPage,
      cssSelector,
      tocSelector,
    };
  }

  /**
   * Find the nearest cssSelector that is an id.
   *
   * @param cssSelector
   * @returns cssSelector that is guaranteed to be an id, or null if no element can be found.
   */
  #findCssSelector(): string | null {
    const firstVisibleCssSelector = this.#findFirstVisibleCssSelector();
    const cssSelector = readium.findFirstVisibleLocator()?.locations?.cssSelector ?? null;
    if (cssSelector == null) {
      return null;
    }

    let selectorElement = document.querySelector(cssSelector) as HTMLElement;
    if (selectorElement == null) {
      if (firstVisibleCssSelector) {
        return firstVisibleCssSelector;
      }

      return null;
    }

    if (selectorElement.id) {
      return `#${selectorElement.id}`;
    }

    if (firstVisibleCssSelector) {
      return firstVisibleCssSelector;
    }

    // Some locators land inside injected spans
    if (selectorElement.nodeType !== Node.ELEMENT_NODE) {
      selectorElement = selectorElement.parentElement;
    }

    // 1. Closest ancestor with ID
    const ancestor = selectorElement.closest('[id]');
    if (ancestor) {
      return `#${ancestor.id}`;
    };

    // 2. Nearest element with ID, either preceding or following the current element in the document order.
    const precedingElementXPath = 'preceding::*[@id][1]';
    const followingElementXPath = 'following::*[@id][1]';

    for (const xpath of [precedingElementXPath, followingElementXPath]) {
      const result = document.evaluate(
        xpath,
        selectorElement,
        null,
        XPathResult.FIRST_ORDERED_NODE_TYPE,
        null
      );

      if (result.singleNodeValue instanceof Element) {
        return `#${result.singleNodeValue.id}`;
      }
    }
  }

  /**
   * Find the nearest cssSelector that is visible, starting from the first visible element and ending at the given cssSelector.
   */
  #findFirstVisibleCssSelector(): string | null {
    const firstVisibleElement = this.#findFirstVisibleElement();
    const lastVisibleElement = this.#findLastVisibleElement();

    if (firstVisibleElement == null || lastVisibleElement == null) {
      return null;
    }

    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = firstVisibleElement;
    let node: Node = firstVisibleElement;

    while (node) {
      if (node instanceof Element && node.id) return `#${node.id}`;

      if (node === lastVisibleElement) break;

      node = walker.nextNode();
    }
  }

  /**
   * Find the preceding Table of Contents element id.
   * @param cssSelector
   * @returns
   */
  #findTocId(cssSelector: string | null): string | null {
    if (this.#tocIds == null || this.#tocIds.length === 0 || cssSelector == null) {
      return null;
    }

    // First check if any of the registered ToC ids are currently visible and return the first one found.
    for (const tocId of this.#tocIds) {
      const tocElement = document.getElementById(tocId);
      if (this.#isElementVisible(tocElement)) {
        return `#${tocId}`;
      }
    }

    // Then find the nearest ToC id to the current cssSelector, either preceding or following in the document order.
    const selectorElement = document.querySelector(cssSelector);
    if (selectorElement == null) {
      return null;
    }

    // If the current element itself is a ToC element, return it immediately.
    if (selectorElement.id && this.#tocIds.includes(selectorElement.id.toLocaleLowerCase())) {
      return `#${selectorElement.id}`;
    }

    // Find the preceding ToC element.
    const predicate = this.#tocIds.map((id) => `@id="${id}"`).join(" or ");

    const precedingElementXPath = `preceding::*[${predicate}][1]`;
    const result = document.evaluate(
      precedingElementXPath,
      selectorElement,
      null,
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    );

    if (result.singleNodeValue instanceof Element) {
      return `#${result.singleNodeValue.id}`;
    }

    // This might be a special case, where we start just before the first ToC element.
    let firstTocElement: Element;
    for (const tocId of this.#tocIds) {
      const tocElement = document.getElementById(tocId);
      if (tocElement) {
        firstTocElement = tocElement;
        break;
      }
    }

    if (firstTocElement == null) {
      // Really shouldn't happen.
      return null;
    }

    // Walk backwards from the first to see if the find the current selector element.
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = firstTocElement;
    let node: Node = firstTocElement;

    while (node) {
      if (node instanceof Element && node === selectorElement) {
        // First ToC element is the current one.
        return `#${firstTocElement.id}`;
      }

      node = walker.previousNode();
    }
  }

  /**
   * Is the given element a page break element, based on EPUB specification or common practices?
   * @param element
   * @returns
   */
  #isPageBreakElement(element: Element | null): boolean {
    if (element == null) {
      return false;
    }

    return element.getAttributeNS("http://www.idpf.org/2007/ops", "type") === 'pagebreak' || element.getAttribute('type') === 'pagebreak' || element.getAttribute('epub:type') === 'pagebreak';
  }

  /**
   * Get the physical page text from the given element, if it is a page break element.
   * @param element
   * @returns
   */
  #getPhysicalPageText(element: HTMLElement): string | null {
    if (!this.#isPageBreakElement(element)) {
      return null;
    }

    return element?.getAttribute('title') ?? element?.innerText.trim();
  }

  /**
   * Find the current physical page index.
   *
   * @returns The physical page index, or null if it cannot be determined.
   */
  #findCurrentPhysicalPage(): string | null {
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
      (prefix: string) => {
        if (prefix === "epub") {
          return "http://www.idpf.org/2007/ops";
        }
        return null;
      },
      XPathResult.FIRST_ORDERED_NODE_TYPE,
      null
    );

    if (result.singleNodeValue instanceof Element && this.#isPageBreakElement(result.singleNodeValue)) {
      return this.#getPhysicalPageText(result.singleNodeValue as HTMLElement);
    }
  }

  /**
   * Find the first visible element in the document.
   * @returns The first visible element, or null if none is found.
   */
  #findFirstVisibleElement(): Element | null {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = document.body.firstElementChild ?? document.body;

    let node = walker.currentNode;
    while (node) {
      if (node instanceof Element && this.#isElementVisible(node)) {
        return node;
      }

      node = walker.nextNode();
    }
  }

  /**
   * Find the last visible element in the document.
   * @returns The last visible element, or null if none is found.
   */
  #findLastVisibleElement() {
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_ELEMENT
    );

    walker.currentNode = document.body.lastElementChild ?? document.body;

    let node = walker.currentNode;
    while (node) {
      if (node instanceof Element && this.#isElementVisible(node)) {
        return node;
      }

      node = walker.previousNode();
    }
  }

  // Functions below was copied from Swift-toolkit - see License.readium-swift-toolkit for details.
  #isElementVisible(element: Element | null): boolean {
    if (this.#shouldIgnoreElement(element)) {
      return false;
    }

    if (readium.isFixedLayout) return true;

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
    epubPage: EpubPage;
  }
}

function Setup() {
  if (window.epubPage) {
    return;
  }

  initResponsiveTables();

  document.removeEventListener('DOMContentLoaded', Setup);
  window.epubPage = new EpubPage();
}

if (document.readyState !== 'loading') {
  window.setTimeout(Setup);
} else {
  document.addEventListener('DOMContentLoaded', Setup);
}
