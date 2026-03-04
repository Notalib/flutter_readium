import { initResponsiveTables } from './Tables';

import { PageInformation, Readium } from 'types';
import './EpubPage.scss';

declare const isIos: boolean;
declare const isAndroid: boolean;
declare const webkit: any;
declare const readium: Readium;

export class EpubPage {
  private get _isScrollModeEnabled(): boolean {
    return getComputedStyle(document.documentElement).getPropertyValue("--USER__view") === "readium-scroll-on";
  }

  public getPageInformation(): PageInformation {
    const physicalPage = this._findCurrentPhysicalPage();
    const locator = readium.findFirstVisibleLocator();
    let page: number | null;
    let totalPages: number | null;
    const cssSelector = locator?.locations?.cssSelector ?? null;

    if (readium.isReflowable) {
      if (this._isScrollModeEnabled) {
        // Page index doesn't make sense in scroll mode.
        page = null;
        totalPages = null;
      } else {
        // Calculate page index based on scroll position and viewport width.
        const { scrollLeft, scrollWidth } = document.scrollingElement;
        const { innerWidth } = window;
        page = Math.round(scrollLeft / innerWidth) + 1;
        totalPages = Math.round(scrollWidth / innerWidth);
      }
    } else {
      // Fixed layout books is single page files.
      page = 1;
      totalPages = 1;
    }

    // Assume fixed layout has only one page, and the physical page index is determined by the current visible element.
    return {
      page,
      totalPages,
      physicalPage,
      cssSelector,
    };
  }

  private _isPageBreakElement(element: Element | null): boolean {
    if (element == null) {
      return false;
    }

    return element.getAttributeNS("http://www.idpf.org/2007/ops", "type") === 'pagebreak' || element.getAttribute('type') === 'pagebreak';
  }

  private _getPhysicalPageIndexFromElement(element: HTMLElement): string | null {
    return element?.getAttribute('title') ?? element?.innerText.trim();
  }

  private _findPhysicalPageIndex(element: Element | null): string | null {
    if (element == null || !(element instanceof Element)) {
      return null;
    } else if (this._isPageBreakElement(element)) {
      return this._getPhysicalPageIndexFromElement(element as HTMLElement);
    }

    return null;
  }

  private _getAllSiblings(elem: ChildNode): HTMLElement[] | null {
    const sibs: HTMLElement[] = [];
    elem = elem?.parentNode?.firstChild as HTMLElement;
    do {
      if (elem?.nodeType === 3) continue; // text node
      sibs.push(elem as HTMLElement);
    } while ((elem = elem?.nextSibling as HTMLElement));
    return sibs;
  }

  /**
   * Find the current physical page index.
   *
   * @returns The physical page index, or null if it cannot be determined.
   */
  private _findCurrentPhysicalPage(): string | null {
    const cssSelector = readium.findFirstVisibleLocator()?.locations?.cssSelector;

    let element = document.querySelector(cssSelector);
    if (element == null) {
      return;
    }

    if (this._isPageBreakElement(element)) {
      return this._getPhysicalPageIndexFromElement(element as HTMLElement);
    }

    while (!!element && element.nodeType === Node.ELEMENT_NODE) {
      const siblings = this._getAllSiblings(element);
      if (siblings == null) {
        return;
      }
      const currentIndex = siblings.findIndex((e) => e?.isEqualNode(element));

      for (let i = currentIndex; i >= 0; i--) {
        const e = siblings[i];

        const pageBreakIndex = this._findPhysicalPageIndex(e);
        if (pageBreakIndex != null) {
          return pageBreakIndex;
        }
      }

      element = element.parentNode as HTMLElement;

      if (element == null || element.nodeName.toLowerCase() === 'body') {
        return document.querySelector("head [name='webpub:currentPage']")?.getAttribute('content');
      }
    }
  }

  private _log(...args: unknown[]) {
    // Alternative for webkit in order to print logs in flutter log outputs.

    if (this._isIos()) {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-call
      webkit?.messageHandlers.log.postMessage(
        // eslint-disable-next-line @typescript-eslint/no-unsafe-call
        [].slice
          .call(args)
          .map((x: unknown) => (x instanceof String ? `${x}` : `${JSON.stringify(x)}`))
          .join(', '),
      );

      return;
    }

    // eslint-disable-next-line no-console
    console.log(JSON.stringify(args));
  }

  private _errorLog(...error: any) {
    this._log(`v===v===v===v===v===v`);
    this._log(`Error:`, error);
    this._log(`Stack:`, error?.stack ?? new Error().stack.replace('\n', '->').replace('_errorLog', ''));
    this._log(`^===^===^===^===^===^`);
  }

  private _isIos(): boolean {
    try {
      return isIos;
    } catch (error) {
      return false;
    }
  }

  private _isAndroid(): boolean {
    try {
      return isAndroid;
    } catch (error) {
      return false;
    }
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
