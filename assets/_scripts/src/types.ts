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

  scrollToPosition(progression: number, direction: string): void;
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
