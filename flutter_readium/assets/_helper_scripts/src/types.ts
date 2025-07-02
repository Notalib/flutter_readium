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
  link: any;
  isFixedLayout: boolean;
  isReflowable: boolean;

  /**
   * @param progression // Position must be in the range [0 - 1], 0-100%.
   */
  scrollToPosition(progression: number): void;

  getColumnCountPerScreen(): void;

  isScrollModeEnabled(): boolean;

  isVerticalWritingMode(): boolean;
  
  // Scroll to the given TagId in document and snap.
  scrollToId(id: string): void;

  scrollToLocator(locator: Locator): void;

  scrollToStart(): void;

  scrollToEnd(): void;

  scrollLeft(): void;

  snapCurrentOffset(): void;

  rangeFromLocator(): Range;

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