import { type ComicKeyframe, type ComicPageSize, type ComicPanel, figureQuerySelector } from './types';
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

const animationEasing = 'cubic-bezier(0.455, 0.030, 0.515, 0.955)';

/**
 * Convert ComicKeyframe array to Web Animation API compatible Keyframes.
 * @param keyframes
 * @returns
 */
function convertToWebAnimationKeyframes(keyframes: ComicKeyframe[]): Keyframe[] {
  const totalDuration = keyframes.reduce((sum, kf) => sum + kf.duration + (kf.holdDuration ?? 0), 0);
  const result: Keyframe[] = [];
  let elapsed = 0;
  for (const kf of keyframes) {
    elapsed += kf.duration;
    const props: Keyframe = {
      top: `${kf.top}px`,
      left: `${kf.left}px`,
      width: `${kf.width}px`,
      height: `${kf.height}px`,
      offset: totalDuration > 0 ? Math.min(1, elapsed / totalDuration) : 1,
      // Apply easing per-segment so each transition gets the full curve,
      // rather than the global easing warping the entire multi-keyframe animation.
      easing: animationEasing,
    };
    if (kf.opacity !== undefined) {
      props.opacity = `${kf.opacity}`;
    }
    result.push(props);
    if (kf.holdDuration) {
      elapsed += kf.holdDuration;
      result.push({ ...props, offset: Math.min(1, elapsed / totalDuration) });
    }
  }

  console.debug("Converted keyframes for Web Animation API:", { input: keyframes, output: result });
  return result;
}

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

  #animation?: Animation;

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

  // Track whether the current/previous frame is the zoomed-out full page, so we
  // can detect the initial zoom *into* a panel (full page -> panel). The clone is
  // created at the full-page position on the "show full page" render, which is a
  // separate (earlier) render than the first panel zoom, so clone existence alone
  // can't distinguish them. Initialised true: every page opens on the full page.
  #currentFrameIsFullPage = true;

  #previousFrameWasFullPage = true;

  readonly #canvasSize!: ComicPageSize;

  #isFullPageFrame(frame: ComicPanel): boolean {
    return frame.top === 0 && frame.left === 0
      && frame.width === this.#canvasSize.width
      && frame.height === this.#canvasSize.height;
  }

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
  async #renderCurrentComicFrame(): Promise<void> {
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
      // If there's an existing image in the container that isn't the clone of the desired images, remove it before rendering the new frame.
      // This usually happens when switch page.
      this.#animation?.cancel();
      this.#animation = undefined;
      this.#container.removeChild(img);
      img = null;
    }

    this.#container.classList.add(activeComicPageContainerClass);

    // The initial zoom is the move *from* the full page view *into* a panel — a
    // much larger scale change than panel-to-panel, so it gets more time. The
    // "show full page" render itself (full page -> full page) is excluded.
    const isInitialZoom = this.#previousFrameWasFullPage && !this.#currentFrameIsFullPage;
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
    const oldAnimation = this.#animation;
    if (oldAnimation) {
      // Cancel the old animation to avoid jank from multiple overlapping animations,
      // but we need to wait for the cancellation to take effect before starting a new animation on the same element,
      // otherwise the new animation may be ignored or behave erratically.
      await new Promise((resolve) => {
        try {
          oldAnimation.addEventListener('finish', resolve);
          oldAnimation.addEventListener('cancel', resolve);
          oldAnimation.cancel();
        } catch {
          // Element may have been detached from the DOM, in which case we can just proceed with the new animation.
          resolve(null);
        }
      });

      this.#animation = undefined;
    }

    const keyframes = ComicBookCalc.makeKeyFrames(currentFrame, canvasSize, this.availableWidth, this.availableHeight, currentDuration, isInitialZoom);
    if (keyframes.length === 0) {
      console.error('No keyframes generated for comic frame animation, cannot render frame.', { canvasSize, currentFrame, currentDuration });
      return;
    }

    // Fallback for browsers without Web Animations API support: jump directly to the
    // focus frame (first keyframe) via inline styles with no animation.
    if (typeof target.animate !== 'function') {
      const focusFrame = keyframes[0];
      target.style.top = `${focusFrame.top}px`;
      target.style.left = `${focusFrame.left}px`;
      target.style.width = `${focusFrame.width}px`;
      target.style.height = `${focusFrame.height}px`;
      return;
    }

    const totalDuration = keyframes.reduce((sum, kf) => sum + kf.duration + (kf.holdDuration ?? 0), 0);
    const animation = target.animate(convertToWebAnimationKeyframes(keyframes), {
      duration: totalDuration,
      // Apply the easing curve at the effect level so single-keyframe moves
      // (cue-to-cue navigation to a normal panel) are eased too.
      // These rely on an implicit offset-0 start keyframe, whose interval is governed by this
      // option-level easing rather than the per-keyframe easing in convertToWebAnimationKeyframes().
      easing: animationEasing,
      fill: 'auto',
    });

    animation.addEventListener('finish', () => {
      console.debug("Animation complete for frame:", currentFrame, "keyframes:", keyframes);
      try {
        animation.commitStyles();
        animation.cancel();
      } catch {
        // Element may have been detached from the DOM.
      }
      this.#animation = undefined;
    });

    this.#animation = animation;
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

    this.#previousFrameWasFullPage = this.#currentFrameIsFullPage;
    this.#currentFrame = comicFrame;
    this.#currentFrameIsFullPage = this.#isFullPageFrame(comicFrame);
    this.#duration = duration;
  }

  public renderCurrentFrame(id: string, duration: number): void {
    this.setCurrentFrame(id, duration);

    void this.#renderCurrentComicFrame();
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
