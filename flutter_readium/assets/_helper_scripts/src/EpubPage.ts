/* eslint-disable @typescript-eslint/restrict-template-expressions */

import { initResponsiveTables } from './Tables';

import { Readium } from 'types';
import './EpubPage.scss';

declare const isIos: boolean;
declare const isAndroid: boolean;
declare const webkit: any;
declare const readium: Readium;
declare const Android: any | null;

export class EpubPage {
  /**
   * Get page fragments.
   */
  public getPageFragments(isVerticalScroll: boolean): string[] {
    try {
      const { scrollLeft, scrollWidth } = document.scrollingElement;

      const { innerWidth } = window;
      const pageIndex = isVerticalScroll ? null : Math.round(scrollLeft / innerWidth) + 1;
      const totalPages = isVerticalScroll ? null : Math.round(scrollWidth / innerWidth);

      return [`page=${pageIndex}`, `totalPages=${totalPages}`];
    } catch (error) {
      this._errorLog(error);

      return [];
    }
  }

  private _isPageBreakElement(element: Element | null): boolean {
    if (element == null) {
      return false;
    }

    return element.getAttribute('type') === 'pagebreak';
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

    const pageBreakElement = element?.querySelector('.page-normal, .page-front, .page-special');

    if (pageBreakElement == null) {
      return null;
    }

    return this._getPhysicalPageIndexFromElement(pageBreakElement as HTMLElement);
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

  public findCurrentPhysicalPage(cssSelector: string): string | null {
    let element = document.querySelector(cssSelector);

    if (element == null) {
      return;
    }

    if (this._isPageBreakElement(element)) {
      return this._getPhysicalPageIndexFromElement(element as HTMLElement);
    }

    while (element.nodeType === Node.ELEMENT_NODE) {
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
