/* eslint-disable @typescript-eslint/restrict-template-expressions */

import { ComicBookPage } from 'ComicBookPage';
import { getCssSelector } from 'css-selector-generator';
import { initResponsiveTables } from './Tables';

import { DomRange, ICurrentHeading, IHeadingElement, Locations, Locator, Readium, Rect } from 'types';
import './EpubPage.scss';

declare const isIos: boolean;
declare const isAndroid: boolean;
declare const webkit: any;
declare const readium: Readium;
declare const comicBookPage: ComicBookPage;
declare const Android: any | null;

export class EpubPage {
  constructor() {
    // Undo line-height in spans broken by ReadiumCSS-before.css.
    // -webkit-line-box-contain: block inline replaced;
    document.documentElement.style.setProperty('-webkit-line-box-contain', 'block inline replaced');
  }

  private readonly _headingTagNames = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'];

  private _allHeadings: IHeadingElement[] | null;

  private readonly _activeLocationId = 'activeLocation';

  private readonly _locationTag = 'span';

  private _documentRange = document.createRange();

  public isReaderReady(): boolean {
    return !!readium;
  }

  // Sets an active location, and optionally navigates to a specific frame in a comic book
  public setLocation(locator: Locator | null, isAudioBookWithText: boolean): void {
    this._debugLog(locator);

    try {
      if (locator == null) {
        this._debugLog('No locator set');

        return;
      }

      this._removeLocation();

      this._setLocation(locator, isAudioBookWithText);

      if (this._isComicBook()) {
        const cssSelector =
          locator?.locations?.cssSelector ?? locator?.locations?.domRange?.start?.cssSelector ?? locator?.locations?.domRange?.end?.cssSelector;

        if (cssSelector == null) {
          this._errorLog('Css selector not set!');
          return;
        }

        const duration = this._getDurationFragment(locator?.locations?.fragments);
        if (duration == null) {
          this._errorLog('Duration not set!');
          return;
        }

        window.GotoComicFrame(cssSelector, duration * 1000);
      }

      // this.debugLog(`setAll END`);
    } catch (error) {
      this._errorLog(error);
    }
  }

  // Scrolls such that the given Locations is visible. If part of the given Locations is
  // already visible, only scrolls to the start of it if toStart is true.
  public scrollToLocations(locations: Locations, isVerticalScroll: boolean, toStart: boolean): boolean {
    try {
      const range = this._processLocations(locations);
      if (range != null) {
        this._scrollToProcessedRange(range, isVerticalScroll, toStart);

        return true;
      }

      const progression = locations.progression;
      if (progression != null) {
        readium?.scrollToPosition(progression);

        return true;
      }

      this._debugLog(`ScrollToLocations: Unknown range`, locations);
    } catch (error) {
      this._errorLog(error);
    }

    return false;
  }

  // Checks whether a given locator is (at least partially) visible.
  public isLocatorVisible(locator: Locator): boolean {
    this._debugLog(locator);

    try {
      const locations = locator.locations;
      const selector = locations.cssSelector ?? locations.domRange?.start?.cssSelector;

      if (this._isComicBook()) {
        const res = document.querySelector(selector) != null;
        this._debugLog(`Comic book`, locations, { found: res, selector });

        return res;
      }

      const range = this._processLocations(locations);
      if (range == null) {
        this._debugLog(`isLocatorVisible: Unknown range`, locations);
        return false;
      }
      // Checks also that the locator also contains `active` class.
      // TODO: This doesn't do what we expect, if the range is visible but not active, this function will return false.
      return this._isProcessedRangeVisible(range) && !!document.querySelector(`${selector} #${this._activeLocationId}`);
    } catch (error) {
      this._errorLog(error);

      // Use true as default to prevent showing the sync button.
      return true;
    }
  }

  // Returns fragments for current location.
  public getLocatorFragments(locator: Locator, isVerticalScroll: boolean): Locator {
    try {
      const cssSelector = locator?.locations?.cssSelector ?? this._findFirstVisibleCssSelector();
      if (cssSelector == null || !cssSelector?.length) {
        this._debugLog('getLocatorFragments: selector not found, returning locator from args');

        return locator;
      }

      const fragments = [...this._getPageFragments(isVerticalScroll), ...this._getTocFragments(cssSelector), ...this._getPhysicalPageFragments(cssSelector)];

      const locatorWithFragments = {
        ...locator,
        locations: {
          cssSelector,
          ...locator.locations,
          fragments: [...(locator.locations?.fragments ?? []), ...fragments],
        },
      };

      return locatorWithFragments;
    } catch (error) {
      this._errorLog(error);

      return locator;
    }
  }

  private _isComicBook(): boolean {
    try {
      return !!comicBookPage?.isComicBook();
    } catch (_) {
      return false;
    }
  }

  private _isTextNode(node: Node) {
    // const TEXT_NODE = 3;
    // const CDATA_SECTION_NODE = 4;
    const nodeType = node.nodeType;
    return nodeType === 3 || nodeType === 4;
  }

  // private
  private _clamp(value: number, min: number, max: number) {
    return Math.min(Math.max(value, min), max);
  }

  // Returns the `Text` node starting at the character with offset `charOffset` in node, splitting
  // the text node if needed to do so. Returns `null` if charOffset is at (or past) the end of node.
  private _findAndSplitOffset(node: Node, charOffset: number): Node | null {
    // Using nested function to make sure node is not returned by reference.
    function process(n: Node): Node | null {
      // TEXT_NODE = 3;
      // CDATA_SECTION_NODE = 4;
      if (n.nodeType === 3 || n.nodeType === 4) {
        const text = n as Text;
        if (charOffset <= 0) {
          return text;
        }

        const length = text.length;
        if (charOffset < length) {
          return text.splitText(charOffset);
        }

        charOffset -= length;
      }

      const children = n.childNodes;
      const childCount = children.length;

      for (let i = 0; i < childCount; ++i) {
        const tn = process(children[i]);

        if (tn != null) {
          return tn;
        }
      }

      return null;
    }

    return process(node);
  }

  // Next node following the end or closing tag of the given node.
  private _nextNodeNotChild(node: HTMLElement | Node): Node | null {
    return node && (node.nextSibling ?? this._nextNodeNotChild(node.parentNode));
  }

  // Next node following the start of the given node, including child nodes.
  private _nextNode(node: HTMLElement | Node): Node {
    return node && (node.firstChild ?? node.nextSibling ?? this._nextNodeNotChild(node.parentNode));
  }

  // Previous node before the beginning or opening tag of the given node.
  private _previousNodeNotChild(node: HTMLElement | Node): Node {
    return node && (node.previousSibling ?? this._previousNodeNotChild(node.parentNode));
  }

  // Previous node before the beginning of the given node, including child nodes.
  private _previousNode(node: HTMLElement | Node): Node {
    return node && (node.lastChild ?? node.previousSibling ?? this._previousNodeNotChild(node.parentNode));
  }

  // First non-whitespace character at or after the given node/charOffset.
  private _findNonWhitespaceForward(node: HTMLElement | Node, charOffset: number) {
    while (node != null) {
      if (this._isTextNode(node)) {
        const data = (node as Text).data;
        charOffset = Math.max(charOffset, 0);

        while (charOffset < data.length) {
          if (data[charOffset].trim() !== '') {
            return {
              node,
              charOffset,
            };
          }

          ++charOffset;
        }

        charOffset = 0;
      }

      node = this._nextNode(node);
    }
  }

  // First non-whitespace character at or before the given node/charOffset.
  private _findNonWhitespaceBackward(node: HTMLElement | Node, charOffset?: number) {
    while (node != null) {
      if (this._isTextNode(node)) {
        const data = (node as Text).data;
        const last = data.length - 1;
        charOffset = Math.min(charOffset ?? last, last);

        while (charOffset >= 0) {
          if (data[charOffset].trim() !== '') {
            return {
              node,
              charOffset,
            };
          }

          --charOffset;
        }

        charOffset = undefined;
      }

      node = this._previousNode(node);
    }
  }

  // First non-whitespace character at or before the given node/charOffset.
  private _findNonWhitespace(node: HTMLElement | Node, charOffset: number) {
    return this._findNonWhitespaceBackward(node, charOffset) ?? this._findNonWhitespaceForward(node, charOffset);
  }

  // Creates a new span specified by locator, with the style attribute given by style. Split into
  // multiple spans if needed.
  private _setLocation(locator: Locator, isAudioBookWithText: boolean) {
    const currentLink = readium.link;
    this._debugLog(`create:`, locator, currentLink);

    const locations = locator.locations;
    const startCssSelector = locations.cssSelector ?? locations?.domRange?.start?.cssSelector;

    if (!startCssSelector) {
      this._errorLog(`Start css selector not found`);

      return;
    }

    const startParent = document.querySelector(startCssSelector);
    if (!startParent) {
      this._errorLog(`Start parent not found`);

      return;
    }

    const endCssSelector = locations?.domRange?.end.cssSelector ?? startCssSelector;
    const endParent = endCssSelector === startCssSelector ? startParent : document.querySelector(endCssSelector);

    if (!endParent) {
      this._errorLog(`End parent not found`);

      return;
    }

    const startOffset = locations?.domRange?.start?.charOffset;
    const endOffset = locations?.domRange?.end?.charOffset;

    // highlight for audiobooks with text
    if (!startOffset && !endOffset && isAudioBookWithText) {
      this._wrapWithLocationElement(startParent);

      return;
    }

    // Iterate over text nodes between startText and endText (if null, use end of parent).
    const startNode = this._findAndSplitOffset(startParent, startOffset) ?? this._nextNodeNotChild(startParent);
    const endNode = this._findAndSplitOffset(endParent, endOffset) ?? this._nextNodeNotChild(endParent);

    const texts = new Array<Text>();

    for (let node = startNode; node && node !== endNode; node = this._nextNode(node)) {
      if (this._isTextNode(node)) {
        texts.push(node as Text);
      }
    }

    for (const text of texts) {
      const locationEl = this._setLocationElement();
      locationEl.appendChild(text.cloneNode(true));
      text.replaceWith(locationEl);
    }
  }

  // Removes a previously-added span (but doesn't remove the contents of the span).
  private _removeLocation() {
    this._debugLog('Remove old location');

    const nodes = document.querySelectorAll<HTMLElement>(`#${this._activeLocationId}`);
    nodes?.forEach((node) => {
      if (this._isAndroid()) {
        // Ugly workaround for randomly changing layout on Android emulator.
        // Leaks lots of useless <span>s.
        node.removeAttribute('id');
        return;
      }

      const parent = node.parentNode;
      node.replaceWith(...node.childNodes);
      parent.normalize();
    });
  }

  // The screen rectangle in horizontal scrolling mode and a slightly shortened screen rectangle in
  // vertical scrolling mode.
  private _safeVisibleRect(isVerticalScroll: boolean): Rect {
    const { innerWidth, innerHeight } = window;

    if (isVerticalScroll) {
      return {
        left: 0,
        top: 0.05 * innerHeight,
        right: innerWidth,
        bottom: 0.95 * innerHeight,
      };
    }
    return {
      left: 0,
      top: 0,
      right: innerWidth,
      bottom: innerHeight,
    };
  }

  private *_descendentTextNodes(node: Node): Generator<Text> {
    if (this._isTextNode(node)) {
      yield node as Text;
    } else {
      for (const child of node.childNodes) {
        yield* this._descendentTextNodes(child);
      }
    }
  }

  private _findTextPosition(node: Node, charOffset: number) {
    // Converts a text offset in a node into something suitable for Range.setStart or Range.setEnd.
    if (node == null) {
      this._errorLog(`findTextPosition: no node, charOffset=${charOffset}`);
      return;
    }

    if (charOffset < 0 || isNaN(charOffset)) {
      this._errorLog(`findTextPosition: invalid charOffset, node=${node.nodeValue}, charOffset=${charOffset}`);
      return;
    }

    if (charOffset === 0) {
      return {
        node,
        charOffset,
      };
    }

    for (const textNode of this._descendentTextNodes(node)) {
      const length = textNode.length;

      if (charOffset <= length) {
        return {
          node: textNode,
          charOffset,
        };
      }

      charOffset -= length;
    }

    this._errorLog(`findTextPosition: failed, node=${this._debugNode(node)}, charOffset=${charOffset}`);

    return;
  }

  private _processDomRange(domRange: DomRange) {
    const { start, end } = domRange;
    const { cssSelector: startSelector, charOffset: startOffset } = start;
    const { cssSelector: endSelector, charOffset: endOffset } = end != null && end !== void 0 ? end : start;
    const startNode = document.querySelector<HTMLElement>(startSelector);
    const startBoundary = this._findTextPosition(startNode, startOffset ?? 0);

    if (startBoundary == null) {
      this._errorLog(`DomRange bad start, selector=${startSelector}`);
      return;
    }

    const endNode = endSelector === startSelector ? startNode : document.querySelector(endSelector);
    const endBoundary = this._findTextPosition(endNode, endOffset != null && endOffset !== void 0 ? endOffset : 0);

    if (endBoundary == null) {
      this._errorLog(`DomRange bad end, selector=${endSelector}`);
      return;
    }

    try {
      this._documentRange.setStart(startBoundary.node, startBoundary.charOffset);
      // this.debugLog(`range.setStart(${startBoundary.node.id ?? startBoundary.node.nodeName}, ${startBoundary.charOffset});`);
    } catch (e) {
      this._errorLog(`${this._debugNode(startBoundary.node)}, ${startBoundary.charOffset}`, e);
      this._documentRange.setStartAfter(startBoundary.node);
    }

    try {
      this._documentRange.setEnd(endBoundary.node, endBoundary.charOffset);
      // this.debugLog(`range.setEnd(${endBoundary.node.id ?? endBoundary.node.nodeName}, ${endBoundary.charOffset});`);
    } catch (e) {
      this._errorLog(`${this._debugNode(endBoundary.node)}, ${endBoundary.charOffset}`, e);
      this._documentRange.setEndAfter(endBoundary.node);
    }

    // Work around possible bad getClientBoundingRect data when the start/end of the range is the
    // same. Browser bug? Seen on an Android device, not sure whether it happens on iOS.
    // https://stackoverflow.com/questions/59767515/incorrect-positioning-of-getboundingclientrect-after-newline-character
    if (this._documentRange.getClientRects().length === 0) {
      const pos = this._findNonWhitespace(startBoundary.node, startBoundary.charOffset);

      if (pos == null) {
        this._errorLog(`Couldn't find any non-whitespace characters in the document!'`);
        return;
      }

      const { node, charOffset } = pos;
      this._documentRange.setStart(node, charOffset);
      this._documentRange.setEnd(node, charOffset + 1);
    }

    return this._documentRange;
  }

  private _processCssSelector(cssSelector: string) {
    const node = document.querySelector(cssSelector);

    if (node == null) {
      this._errorLog(`processCssSelector: error: node not found ${cssSelector}`);
      return;
    }

    // Make sure node is visible on the page in order to get the range.
    if (window.getComputedStyle(node).display === 'none') {
      (node as HTMLElement).style.display = this._isPageBreakElement(node) ? 'flex' : 'block';
    }

    this._documentRange.selectNode(node);
    return this._documentRange;
  }

  private _processLocations(locations: Locations): Range | null {
    if (locations == null) {
      this._errorLog('location not set');

      return;
    }

    if (locations.domRange) {
      return this._processDomRange(locations.domRange);
    }

    const selector = locations.cssSelector ?? locations.domRange?.start?.cssSelector;
    if (selector) {
      return this._processCssSelector(selector);
    }
  }

  private _scrollToProcessedRange(range: Range, isVerticalScroll: boolean, toStart: boolean) {
    if (toStart || !this._isProcessedRangeVisible(range)) {
      this._scrollToBoundingClientRect(range, isVerticalScroll);
    }
  }

  private _scrollToBoundingClientRect(range: Range, isVerticalScroll: boolean) {
    const { top, right, bottom, left } = range.getBoundingClientRect();

    if (top === 0 && right === 0 && bottom === 0 && left === 0) {
      this._debugLog(`scrollToBoundingClientRect: Scrolling to defective bounding rect, abort! `, range.getClientRects(), range.getClientRects().length);
      return;
    }

    const { scrollLeft, scrollWidth, scrollTop, scrollHeight } = document.scrollingElement;

    if (isVerticalScroll) {
      const { top: minHeight, bottom: maxHeight } = this._safeVisibleRect(isVerticalScroll);

      if (top < minHeight || bottom > maxHeight) {
        const offset = this._clamp((scrollTop + top - minHeight) / scrollHeight, 0, 1);
        readium?.scrollToPosition(offset);
      }
    } else {
      const offset = (scrollLeft + 0.5 * (left + right)) / scrollWidth;
      readium?.scrollToPosition(offset);
    }
  }

  private _isProcessedRangeVisible(range: Range) {
    const { innerWidth, innerHeight } = window;
    const { top, right, bottom, left } = range.getBoundingClientRect();
    return top < innerHeight && 0 < bottom && left < innerWidth && 0 < right;
  }

  private _getPageFragments(isVerticalScroll: boolean): string[] {
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

  private _getDurationFragment(fragments: string[]): number | null {
    try {
      const durationFragment = fragments.find((fragment) => fragment.includes('duration='));
      if (!durationFragment) {
        this._errorLog('Duration fragment not found.');
        return;
      }

      const durationMatch = /duration=(\d+(?:\.\d+)?)/.exec(durationFragment);
      if (!durationMatch) {
        this._errorLog('Invalid duration format.');
        return;
      }

      this._debugLog(`Duration fragment:`, durationMatch[1]);
      return parseFloat(durationMatch[1]);
    } catch (error) {
      this._errorLog('Could not retrieve duration fragment!');
      return;
    }
  }

  private _getTocFragments(selector: string): string[] {
    try {
      const headings = this._findPrecedingAncestorSiblingHeadings(selector);
      const id = headings[0]?.id;
      if (id == null) {
        return [];
      }

      return [`toc=${id}`];
    } catch (error) {
      this._errorLog(error);

      return [];
    }
  }

  private _getPhysicalPageFragments(selector: string): string[] {
    try {
      const currentPhysicalPage = this._findCurrentPhysicalPage(selector);

      if (currentPhysicalPage == null) {
        return [];
      }

      return [`physicalPage=${currentPhysicalPage}`];
    } catch (error) {
      this._errorLog(`Selector:${selector} -- ${error}`);

      return [];
    }
  }

  // TODO: Code below is from Thorium project.
  //       Use Intersection Observer API instead:
  //       https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
  private _findPrecedingAncestorSiblingHeadings(selector: string | null): ICurrentHeading[] | null {
    const selectorElement = document.querySelector(selector);

    // Check if the element contains any heading before finding parent or sibling heading.
    const currentElement = selectorElement?.querySelectorAll(this._headingTagNames.join(','))[0] ?? selectorElement;

    if (currentElement == null) {
      return;
    }

    if (!this._allHeadings) {
      const headingElements = Array.from(window.document.querySelectorAll(this._headingTagNames.join(',')));
      for (const hElement of headingElements) {
        if (hElement) {
          const el = hElement;
          const t = el.textContent || el.getAttribute('title') || el.getAttribute('aria-label');
          let i = el.getAttribute('id');
          if (!i) {
            // common authoring pattern: parent section (or other container element) has the navigation target anchor
            let cur = el;
            let p: Element | null;
            while ((p = cur.parentNode as Element | null) && p?.nodeType === Node.ELEMENT_NODE) {
              if (p.firstElementChild !== cur) {
                break;
              }

              const di = p.getAttribute('id');
              if (di) {
                i = di;
                break;
              }

              cur = p;
            }
          }
          const heading: IHeadingElement = {
            element: el,
            id: i ? i : null,
            level: parseInt(el.localName.substring(1), 10),
            text: t,
          };
          if (!this._allHeadings) {
            this._allHeadings = [];
          }
          this._allHeadings.push(heading);
        }
      }

      if (!this._allHeadings) {
        this._allHeadings = [];
      }
    }

    let arr: ICurrentHeading[] | null;
    for (let i = this._allHeadings.length - 1; i >= 0; i--) {
      const heading = this._allHeadings[i];

      const c = currentElement.compareDocumentPosition(heading.element);

      // eslint-disable-next-line no-bitwise
      if (c === 0 || c & Node.DOCUMENT_POSITION_PRECEDING || c & Node.DOCUMENT_POSITION_CONTAINS) {
        if (!arr) {
          arr = [];
        }

        // Don't add the heading since the id is missing and it means that toc element does not
        // points to this heading. Probably the element is wrapped in `body` or `section` element
        // which will handled further below.
        if (heading?.id) {
          arr.push({
            id: heading.id,
            level: heading.level,
            text: heading.text,
          });
        }
      }
    }

    if (arr?.length) {
      return arr;
    }

    // No heading found try with closes section or body
    const closetSectionOrBody = selectorElement.closest('section') ?? selectorElement.closest('body');
    if (closetSectionOrBody) {
      return [
        {
          id: closetSectionOrBody.id,
          level: 0,
          text: closetSectionOrBody.innerText,
        },
      ];
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

  private _findCurrentPhysicalPage(cssSelector: string): string | null {
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

  private _findFirstVisibleCssSelector(): string {
    const selector = this._getCssSelector(this._getFirstVisibleElement());

    return selector;
  }

  private _getCssSelector(element: Element): string {
    try {
      const selector = getCssSelector(element, {
        root: document.querySelector('body'),
      });

      // Sometimes getCssSelector returns `:root > :nth-child(2)` instead of `body`
      // In such cases, replace it with `body`
      const cssSelector = selector?.replace(':root > :nth-child(2)', 'body')?.trim() ?? 'body';

      this._debugLog(cssSelector);

      return cssSelector;
    } catch (error) {
      this._errorLog(error);

      return 'body';
    }
  }

  private _getFirstVisibleElement(): Element {
    const element = this._findFirstVisibleElement(document.body);

    this._debugLog(`First visible element:`, {
      tagName: element.nodeName.toLocaleLowerCase(),
      id: element.id,
      className: element.className,
    });

    return element;
  }

  private _findFirstVisibleElement(node: Element): Element {
    const nodeData = {
      tagName: node.nodeName.toLocaleLowerCase(),
      id: node.id,
      className: node.className,
    };

    for (const child of node.children) {
      const childData = {
        tagName: child.nodeName.toLocaleLowerCase(),
        id: child.id,
        className: child.className,
      };

      if (!this._isElementVisible(child)) {
        // Uncomment only when debugging.
        // this._debugLog(`Not visible - continue`, childData);

        continue;
      }

      if (this._shouldIgnoreElement(child)) {
        this._debugLog(`Element is ignored - continue`, childData);

        continue;
      }

      if (child.id.includes(`${this._activeLocationId}`)) {
        this._debugLog(`Child is an active location element, return closest element with id`, { childData, nodeData });

        return node.id ? node : this._findClosestElementWithId(child);
      }

      if (child.hasChildNodes()) {
        this._debugLog(`Loop into children`, childData);

        return this._findFirstVisibleElement(child);
      }

      // This should not happens
      if (!child.id) {
        this._debugLog(`Element has no ID attribute - return closest element with id`, childData);

        return node.id ? node : this._findClosestElementWithId(child);
      }
    }

    this._debugLog(`return:`, nodeData);

    return node;
  }

  private _findClosestElementWithId(element: Element): Element | null {
    let currentElement = element.parentElement;

    while (currentElement !== null) {
      if (currentElement.id) {
        return currentElement;
      }
      currentElement = currentElement.parentElement;
    }

    this._debugLog('No element with id attr found!');
    return element;
  }

  // Returns first visible element in viewport.
  // True `fullVisibility` will ignore the element if it starts on previous pages.
  private _isElementVisible(element: Element, fullVisibility = false): boolean {
    if (readium?.isFixedLayout) {
      return true;
    }

    if (element === document.body || element === document.documentElement) {
      return true;
    } else if (!document || !document.documentElement || !document.body) {
      return false;
    }

    const rect = element.getBoundingClientRect();

    if (fullVisibility) {
      if (this._isScrollModeEnabled()) {
        return rect.top >= 0 && rect.top <= document.documentElement.clientHeight;
      }

      if (rect.left >= 1) {
        return true;
      }

      return false;
    }

    if (this._isScrollModeEnabled()) {
      return rect.bottom > 0 && rect.top < window.innerHeight;
    }

    return rect.right > 0 && rect.left < window.innerWidth;
  }

  private _shouldIgnoreElement(element: Element): boolean {
    const elStyle = window.getComputedStyle(element);
    if (elStyle) {
      const display = elStyle.getPropertyValue('display');
      if (display === 'none') {
        return true;
      }
      // Cannot be relied upon, because web browser engine reports invisible when out of view in
      // scrolled columns!
      // const visibility = elStyle.getPropertyValue("visibility");
      // if (visibility === "hidden") {
      //     return false;
      // }
      const opacity = elStyle.getPropertyValue('opacity');
      if (opacity === '0') {
        return true;
      }
    }

    return this._isElementEmpty(element);
  }

  private _isElementEmpty(element: Element): boolean {
    const nodeName = element.tagName.toLowerCase();
    if (nodeName === 'img') {
      return false;
    }

    return element.textContent.trim() === '';
  }

  private _wrapWithLocationElement(el: Element): void {
    const parentElement = el;

    if (parentElement) {
      const locationEl = this._setLocationElement();

      while (parentElement.firstChild) {
        const child = parentElement.firstChild;
        parentElement.removeChild(child);
        locationEl.appendChild(child);
      }

      parentElement.appendChild(locationEl);
    }
  }

  private _setLocationElement() {
    const el = document.createElement(this._locationTag);
    el.id = this._activeLocationId;

    return el;
  }

  private _isScrollModeEnabled() {
    const style = document.documentElement.style;
    return (
      style.getPropertyValue('--USER__view').trim() === 'readium-scroll-on' ||
      // FIXME: Will need to be removed in Readium 3.0, --USER__scroll was incorrect.
      style.getPropertyValue('--USER__scroll').trim() === 'readium-scroll-on'
    );
  }

  private _debugLog(...args: unknown[]) {
    this._log(`=======Flutter Readium Debug=====`);
    this._log(args);
    this._log(`=================================`);
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

  private _debugNode(node: HTMLElement | Node | null): string | undefined {
    if (node instanceof Node) {
      const xmlSerializer = new XMLSerializer();
      return xmlSerializer.serializeToString(node);
    } else if ('innerHTML' in node || 'textContent' in node) {
      const element = node as HTMLElement;
      return element.innerHTML ?? element.textContent ?? '?';
    }
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
