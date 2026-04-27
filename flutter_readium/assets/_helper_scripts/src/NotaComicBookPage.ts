import animejs, { type AnimeInstance } from 'animejs';
import { type ComicPageSize, type ComicPanel, figureQuerySelector } from './types';
import { ComicBookCalc } from './ComicBookCalc';
import './NotaComicBookPage.scss';

const activeComicPageContainerClass = 'nota-comic-is-active';

function sanitizeId(id: string): string {
  return id.toLocaleLowerCase().replace(/^#/g, '');
}

export class NotaComicBook {
  // Singleton instance
  static #instance: NotaComicBook | null = null;

  // Store the original scrollToId function to call for non-comic content, if it doesn't exist we provide a fallback that just scrolls the element into view.
  #originalScrollToIdFn = window.readium?.scrollToId ?? ((id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  });

  constructor() {
    // Singleton pattern to ensure only one instance of NotaComicBook is created.
    if (NotaComicBook.#instance) {
      return NotaComicBook.#instance;
    }

    NotaComicBook.#instance = this;

    const figureElements = [...document.querySelectorAll<HTMLElement>(figureQuerySelector)];
    if (figureElements.length === 0) {
      console.debug('This page does not appear to be a comic book page. NotaComicBookPage will not be initialized.');
      return this;
    }

    this.#container = document.createElement('div');
    this.#container.classList.add('nota-comicbook-page-container');
    document.body.appendChild(this.#container);

    this.#comicBookPages = figureElements.map((figureElement) => new NotaComicBookPage(figureElement, this.#container));

    if (typeof window.readium !== 'undefined') {
      // We need to capture scrollToId calls to handle scrolling to comic frames, but we want to preserve the original functionality for non-comic content. So we override scrollToId to route through our custom function, and keep a reference to the original function for non-comic use.
      window.readium.scrollToId = (id: string) => {
        this.scrollToId(id);
      };
    }

    window.addEventListener('resize', this.#onResize);
  }

  public segmentDuration: number = 1000;

  readonly #comicBookPages: NotaComicBookPage[] = [];

  #lastElementId: string | null = null;

  #container!: HTMLDivElement;

  #getComicBookPageByFrameId(id: string): NotaComicBookPage | undefined {
    return this.#comicBookPages.find((page) => !!page.getComicArea(id));
  }

  public scrollToId(id: string, duration: number = this.segmentDuration): void {
    if (!id) {
      console.warn("scrollToId called with empty id, doing nothing");
      this.#originalScrollToIdFn.call(window.readium, id);
      return;
    }

    this.#lastElementId = id;

    const lcId = sanitizeId(id);
    const page = this.#getComicBookPageByFrameId(lcId);
    if (!page) {
      // Not a comic book page, so we need to use the original scrollToId function to scroll to the element,
      // and remove the active comic page container class to reset any comic page specific styling or behavior.
      this.#container.classList.remove(activeComicPageContainerClass);
      for (let child of this.#container.childNodes) {
        this.#container.removeChild(child);
      }

      this.#originalScrollToIdFn.call(window.readium, id);
      return;
    }

    page.gotoComicFrame(lcId, duration ?? this.segmentDuration ?? 1000);
  }

  public gotoComicFrame(id: string, duration?: number) {
    this.scrollToId(id, duration);
  }

  #onResize = (): void => this.scrollToId(this.#lastElementId ?? '');
}

const animationEasing = 'cubicBezier(0.455, 0.030, 0.515, 0.955)';

export class NotaComicBookPage {
  constructor(figureElement: HTMLElement, container: HTMLDivElement) {
    const comicImg = figureElement.querySelector<HTMLImageElement>('img:first-child');
    if (comicImg == null) {
      console.error(`No image with class "page" found within figure element. This really shouldn't happen.`);
      return this;
    }

    figureElement.classList.add('nota-comicbook-page');
    const figureId = figureElement.id;
    const comicImgId = comicImg.id || figureId;
    if (comicImgId == figureId) {
      figureElement.removeAttribute('id');
      comicImg.id = comicImgId;
    }

    this.#comicImg = comicImg;
    this.#container = container;
    this.#canvasSize = this.#extractCanvasSize();

    // reset to readium-css
    this.#comicImg.style.width = "unset";
    this.#comicImg.style.height = "unset";

    const canvasFrame = this.#fullPageComicFrame;

    this.#setComicAreaData(figureId, canvasFrame);
    this.#setComicAreaData(comicImgId, canvasFrame);

    for (const area of figureElement.querySelectorAll<HTMLDivElement>('div.area')) {
      const frame = this.#extractComicFrame(area);
      this.#setComicAreaData(area.id, frame);
      // area.style.display = 'none';
    }

    // Set the current frame to the full page.
    this.setCurrentFrame(this.#comicImg.id, 0);
  }

  /**
   * Set comic area frame to the map, handle id naming.
   *
   * @param id - id of the area
   * @param frame - frame of the area
   */
  #setComicAreaData(id: string, frame: ComicPanel): void {
    if (!id) {
      return;
    }

    this.#comicAreas.set(sanitizeId(id), frame);
  }

  /**
   * Get comic area frame from the map, handle naming.
   *
   * @param id - id of the area
   */
  public getComicArea(id: string): ComicPanel | undefined {
    const sanitizedId = sanitizeId(id);
    if (!this.#comicAreas.has(sanitizedId)) {
      return;
    }

    return Object.freeze({ ...this.#comicAreas.get(sanitizedId)! });
  }

  #animeInstance?: AnimeInstance;

  public segmentDuration: number = 1000;

  #container!: HTMLElement;

  protected get availableWidth(): number {
    return this.#container.clientWidth;
  }

  protected get availableHeight(): number {
    return this.#container.clientHeight;
  }

  readonly #comicImg!: HTMLImageElement;

  readonly #comicAreas = new Map<string, ComicPanel>();

  #currentFrame!: ComicPanel;

  #duration!: number;

  readonly #canvasSize!: ComicPageSize;

  /**
   * Full page comic book frame
   */
  get #fullPageComicFrame(): ComicPanel {
    return Object.freeze({
      ...this.#canvasSize,
      left: 0,
      top: 0,
    });
  }

  /**
   * Render the comic book frame
   */
  #renderCurrentComicFrame(): void {
    const canvasSize = this.#canvasSize;
    const currentFrame = this.#currentFrame;
    const currentDuration = this.#duration;

    if (canvasSize == null || currentFrame == null || currentDuration == null) {
      console.error('Cannot render comic frame - missing data', { canvasSize, currentFrame, currentDuration });
      return;
    }

    let img = this.#container.querySelector('img');
    const frameId = this.#comicImg.id;
    const cloneId = `${frameId}-clone`;
    if (img && img.id !== cloneId) {
      animejs.remove(img);
      this.#container.removeChild(img);
      img = null;
    }

    this.#container.classList.add(activeComicPageContainerClass);

    if (!img) {
      img = this.#comicImg.cloneNode(false) as HTMLImageElement;
      img.id = cloneId;
      const frame = ComicBookCalc.calcFullPageComicFrame(canvasSize, this.availableWidth, this.availableHeight);
      img.style.width = `${frame.width}px`;
      img.style.height = `${frame.height}px`;
      img.style.left = `${frame.left}px`;
      img.style.top = `${frame.top}px`;
      this.#container.prepend(img);
    }

    const target = img;
    if (target == null) {
      console.error('Cannot render comic frame - missing data', { canvasSize, currentFrame, currentDuration, comicImg: target });
      return;
    }

    // Remove old animation
    this.#animeInstance?.pause();
    animejs.remove(target);

    const keyframes = ComicBookCalc.makeKeyFrames(currentFrame, canvasSize, this.availableWidth, this.availableHeight, currentDuration);

    this.#animeInstance = animejs({
      targets: target,
      keyframes,
      easing: animationEasing,
      complete: () => {
        console.debug("Animation complete for frame:", currentFrame, "keyframes:", keyframes);

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
  }

  public renderCurrentFrame(id: string, duration: number): void {
    this.setCurrentFrame(id, duration);

    this.#renderCurrentComicFrame();
  }

  public gotoComicFrame(id: string, duration: number) {
    this.renderCurrentFrame(sanitizeId(id), duration);
  };

  #extractComicFrame(area: HTMLDivElement): ComicPanel {
    const frame: ComicPanel = {
      height: 0,
      width: 0,
      left: 0,
      top: 0,
    };

    for (const key of Object.keys(frame) as (keyof ComicPanel)[]) {
      const value = this.#getStylePixelValue(area, key);
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
  #getStylePixelValue(element: HTMLElement, key: string): number | null {
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

  #extractCanvasSize(): ComicPageSize {
    const frame: ComicPageSize = {
      height: 0,
      width: 0,
    };

    for (const key of Object.keys(frame) as (keyof ComicPageSize)[]) {
      const value = this.#getStylePixelValue(this.#comicImg, key);
      if (value == null) {
        console.error(`${this.#comicImg.id} is missing style[${key}]`);
        continue;
      }

      frame[key] = value;
    }

    return Object.freeze(frame);
  }
}

Object.defineProperty(window, 'isNotaComicBook', {
  value: () => {
    const figureElements = document.querySelectorAll<HTMLElement>(figureQuerySelector);
    return figureElements.length > 0;
  },
  writable: false,
  configurable: false,
});
