export interface CanvasSize {
  height: number;
  width: number;
}

export interface ComicFrame extends CanvasSize {
  left: number;
  top: number;
}

export interface ComicFramePosition {
  width: number;
  height: number;
  topLeft: {
    x: number;
    y: number;
  };
  bottomRight: {
    x: number;
    y: number;
  };
}

/**
 * Readium JS library injected by kotlin/swift-toolkit.
 **/
export interface Readium {
  get isFixedLayout(): boolean | undefined;
  get isReflowable(): boolean | undefined;

  /**
   * @param progression // Position must be in the range [0 - 1], 0-100%.
   */
  scrollToPosition(progression: number): void;

  /**
   * Scroll to the given TagId in document and snap.
   */
  scrollToId(id: string): void;

  /**
   * Scrolls to the first occurrence of the given text snippet.
   *
   * The expected text argument is a Locator object, as defined here:
   * https://readium.org/architecture/models/locators/
   */
  scrollToLocator(locator: Locator): void;

  scrollToStart(): void;

  scrollToEnd(): void;

  scrollLeft(): void;

  scrollRight(): void;

  setCSSProperties(properties: Record<string, string>): void;

  setProperty(key: string, value: string): void;

  removeProperty(key: string): void;

  getCurrentSelection(): CurrentSelection;

  registerDecorationTemplates(newStyles: Record<string, any>): void;

  getDecorations(groupName: string): Record<string, any>;

  findFirstVisibleLocator(): Locator | null;
}

export interface Locator {
  href: string;
  locations: Locations | null;
}

export interface Locations {
  cssSelector: string | null;
  progression: number | null;
  totalProgression: number | null;
  fragments: string[] | null;
  domRange: DomRange | null;
}

export interface DomRange {
  start: CSSBoundary;
  end: CSSBoundary;
}

export interface CSSBoundary {
  cssSelector: string;
  textNodeIndex: number;
  charOffset: number;
}

export interface Rect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface IHeadingElement {
  element: Element;
  level: number;
  text: string | undefined;
  id: string | undefined;
}

export interface ICurrentHeading {
  id: string | undefined;
  text: string | undefined;
  level: number;
}

export interface CurrentSelectionText {
  highlight: string;
  before: string;
  after: string;
}

export interface CurrentSelectionRect {
  width: number;
  height: number;
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface CurrentSelection {
  text: CurrentSelectionText;
  rect: CurrentSelectionRect;
}

export interface PageInformation {
  /**
   * The physical page number, if available. This is a string because it can contain non-numeric characters, such as "iv" or "xii". It can also be null if the physical page number is not available.
   */
  physicalPage?: string | null;

  /**
   * The CSS selector for the first visible element in the current viewport.
   *
   * These are used to make more precise locators in the native layer.
   */
  cssSelector?: string | null;

  /**
   * The id of the nearest ToC element to the current reading position. Either the first visible ToC element id or the nearest preceding ToC element id. This is null if no ToC element is found.
   */
  tocId?: string | null;
}
