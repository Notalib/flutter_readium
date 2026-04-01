import animejs, { AnimeInstance } from 'animejs';
import { CanvasSize, ComicFrame, figureQuerySelector, Readium } from './types';
import { ComicBookCalc } from './ComicBookCalc';
import './NotaComicBookPage.scss';

declare const readium: Readium | undefined;

const BLACK_AND_WHITE_MODE_KEY = 'black-and-white-rendering';

const blackAndWhiteCssClass = 'black-white-comic-mode';

function sanitizeId(id: string): string {
  return id.toLocaleLowerCase().replace(/^#/g, '');
}

export class NotaComicBook {
  // Singleton instance
  private static instance: NotaComicBook | null = null;

  constructor() {
    // Singleton pattern to ensure only one instance of NotaComicBook is created.
    if (NotaComicBook.instance) {
      return NotaComicBook.instance;
    }

    NotaComicBook.instance = this;

    const figureElements = [...document.querySelectorAll<HTMLElement>(figureQuerySelector)];
    if (figureElements.length === 0) {
      console.debug('This page does not appear to be a comic book page. NotaComicBookPage will not be initialized.');
      return this;
    }

    if (NotaComicBook.isBlackAndWhiteEnabled()) {
      NotaComicBook.setBlackAndWhiteMode(true);
    }

    this._comicBookPages = figureElements.map((figureElement) => new NotaComicBookPage(figureElement));

    if (this._comicBookPages.length > 0) {
      document.body.classList.add('comicBody');
    }

    if (typeof readium !== 'undefined') {

      const originalScrollToIdFn = readium.scrollToId;
      readium.scrollToId = (id: string) => {
        if (!id) {
          console.log("scrollToId called with empty id, delegating to original function");
          // originalScrollToIdFn.call(readium, id);
          return;
        }

        const lcId = sanitizeId(id);

        const page = this.getComicBookPageByFrameId(lcId);
        console.log("scrollToId called with id:", id, "mapped to lcId:", lcId, "found page:", page);
        if (!page) {
          originalScrollToIdFn.call(readium, id);
          return;
        }

        page.gotoComicFrame(lcId, this.segmentDuration ?? 1000);
      };

      Object.entries(readium).forEach(([key, value]) => {
        if (key === 'scrollToId') {
          return;
        }

        if (typeof value !== 'function') {
          return;
        }

        const originalFunction = value;
        (readium as any)[key] = (...args: any[]) => {
          console.log(`Readium method "${key}" called with arguments:`, args);

          return originalFunction.apply(readium, args);
        };
      });
    }
  }

  public segmentDuration: number = 1000;

  private _comicBookPages: NotaComicBookPage[];

  private getComicBookPageByFrameId(id: string): NotaComicBookPage | undefined {
    return this._comicBookPages.find((page) => !!page.getComicArea(id));
  }

  public static isBlackAndWhiteEnabled() {
    return window.sessionStorage.getItem(BLACK_AND_WHITE_MODE_KEY) === 'true';
  }

  public gotoComicFrame(id: string, duration: number) {
    const page = this.getComicBookPageByFrameId(id);
    if (!page) {
      console.error(`gotoComicFrame: No comic book page found for id "${id}"`);
      return;
    }

    page.gotoComicFrame(id, duration ?? this.segmentDuration ?? 1000);
  }

  public static setBlackAndWhiteMode(enable: boolean) {
    window.sessionStorage.setItem(BLACK_AND_WHITE_MODE_KEY, enable ? 'true' : 'false');

    if (enable) {
      document.body.classList.add(blackAndWhiteCssClass);
    } else {
      document.body.classList.remove(blackAndWhiteCssClass);
    }
  }
}

const animationEasing = 'cubicBezier(0.455, 0.030, 0.515, 0.955)';
export class NotaComicBookPage {
  constructor(figureElement: HTMLElement) {
    const comicImg = figureElement.querySelector<HTMLImageElement>('img:first-child');
    if (comicImg == null) {
      console.error(`No image with class "page" found within figure element. This really shouldn't happen.`);
      return this;
    }

    figureElement.classList.add('nota-comicbook-page');
    const figureId = figureElement.id;
    const comicImgId = comicImg.id || figureId;
    if (comicImgId == figureId) {
      figureElement.id = null;
      comicImg.id = comicImgId;
    }

    this.#comicImg = comicImg;
    this.#container = figureElement;

    const canvasFrame = this.#fullPageComicFrame;

    if (figureId) {
      this.#setComicArea(figureId, canvasFrame);
    }
    if (comicImgId) {
      this.#setComicArea(comicImgId, canvasFrame);
    }

    for (const area of figureElement.querySelectorAll<HTMLDivElement>('div.area')) {
      const frame = this.#extractComicFrame(area);
      this.#setComicArea(area.id, frame);
      area.style.display = 'none';
    }

    window.addEventListener('resize', this.#onResize);

    console.log("frame areas:", this.#comicAreas);

    // Make sure whole comic image is visible on start.
    this.setCurrentFrame(this.#comicImg.id, 0);
  }

  /**
   * Set comic area frame to the map, handle naming.
   *
   * @param id - id of the area
   * @param frame - frame of the area
   */
  #setComicArea(id: string, frame: ComicFrame): void {
    this.#comicAreas.set(sanitizeId(id), frame);
  }

  /**
   * Get comic area frame from the map, handle naming.
   *
   * @param id - id of the area
   */
  public getComicArea(id: string): ComicFrame | undefined {
    id = sanitizeId(id);

    return this.#comicAreas.get(id);
  }

  #animeInstance?: AnimeInstance;

  public segmentDuration: number = 1000;

  #container: HTMLElement;

  protected get availableWidth(): number {
    return this.#container.clientWidth;
  }

  protected get availableHeight(): number {
    return this.#container.clientHeight;
  }

  #comicImg: HTMLImageElement;

  #comicAreas = new Map<string, ComicFrame>();

  #currentFrame: ComicFrame;

  #duration: number;

  /**
   * Full page comic book frame
   */
  get #fullPageComicFrame(): ComicFrame {
    return {
      ...this.#canvasSize,
      left: 0,
      top: 0,
    };
  }

  /**
   * Render the comic book frame
   */
  #renderCurrentComicFrame(): void {
    const canvasSize = this.#canvasSize;
    const currentFrame = this.#currentFrame;
    const currentDuration = this.#duration;
    const comicImg = this.#comicImg;
    if (canvasSize == null || currentFrame == null || currentDuration == null || comicImg == null) {
      console.error('Cannot render comic frame - missing data', { canvasSize, currentFrame, currentDuration, comicImg });
      return;
    }

    // Remove old animation
    this.#animeInstance?.pause();
    animejs.remove(comicImg);

    const keyframes = ComicBookCalc.MakeKeyFrames(currentFrame, canvasSize, this.availableWidth, this.availableHeight, currentDuration);

    this.#animeInstance = animejs({
      targets: comicImg,
      keyframes,
      easing: animationEasing,
      complete: () => {
        console.log("Animation complete for frame:", currentFrame, "keyframes:", keyframes);

        this.#animeInstance = undefined;
      }
    });
  }

  /**
   * Set current comic frame from id and duration
   */
  public setCurrentFrame(id: string, duration: number): void {
    const comicFrame = this.getComicArea(id);
    if (!comicFrame) {
      console.error(`setCurrentFrame(${id}) - not found`);
      return;
    }

    this.#currentFrame = comicFrame;
    this.#duration = duration;

    this.#renderCurrentComicFrame();
  }

  public gotoComicFrame(id: string, duration: number) {
    id = sanitizeId(id);
    const headingElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6');

    this.setCurrentFrame(id, duration);

    const activeElement = document.getElementById(id);
    if (activeElement?.classList.contains('area') || activeElement?.tagName.toLowerCase() === 'img' || activeElement?.tagName.toLowerCase() === 'figure') {
      headingElements.forEach((e) => e.classList.add('hideHeading'));
    } else {
      headingElements.forEach((e) => e.classList.remove('hideHeading'));
      this.setCurrentImageFrame();
    }
  };

  /**
   * Set current comic frame to the image element.
   */
  public setCurrentImageFrame(): void {
    if (this.#comicImg == null) {
      console.error('setCurrentImageFrame() - no comicImg');
      return;
    }

    this.setCurrentFrame(this.#comicImg.id, 1000);
  }

  #extractComicFrame(area: HTMLDivElement): ComicFrame {
    const frame: ComicFrame = {
      height: 0,
      width: 0,
      left: 0,
      top: 0,
    };

    for (const key of Object.keys(frame) as (keyof ComicFrame)[]) {
      const value = this.getStylePixelValue(area, key);
      if (value == null) {
        continue;
      }

      frame[key] = value;
    }

    return frame;
  }

  /**
   * Helper for getting the pixel value from the element's style, with error handling.
   * Used for frame and canvas size extraction.
   *
   * @param element
   * @param key
   * @returns Pixel number value or null if not found or not in pixels
   */
  private getStylePixelValue(element: HTMLElement, key: string): number | null {
    const value = element.style.getPropertyValue(key);
    if (!value) {
      console.error(`${element.id} is missing style[${key}]`);
      return null;
    }

    if (!value.endsWith('px')) {
      console.error(`${element.id} style[${key}] value "${value}" is not in pixels`);
      return null;
    }

    return parseInt(value.replace(/px$/, ''), 10);
  }

  get #canvasSize(): CanvasSize {
    const dataKey = 'canvasSize';

    if (this.#comicImg.dataset[dataKey]) {
      return JSON.parse(this.#comicImg.dataset[dataKey]) as CanvasSize;
    }

    const frame: CanvasSize = {
      height: 0,
      width: 0,
    };

    for (const key of Object.keys(frame) as (keyof CanvasSize)[]) {
      const value = this.getStylePixelValue(this.#comicImg, key);
      if (value == null) {
        console.error(`${this.#comicImg.id} is missing style[${key}]`);
        continue;
      }

      frame[key] = value;
    }

    this.#comicImg.dataset[dataKey] = JSON.stringify(frame);

    return frame;
  }

  #onResize = (): void => this.#renderCurrentComicFrame();
}

Object.defineProperty(window, 'isNotaComicBook', {
  value: () => {
    const figureElements = document.querySelectorAll<HTMLElement>(figureQuerySelector);
    return figureElements.length > 0;
  },
  writable: false,
  configurable: false,
});
