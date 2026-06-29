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

    // Auto-mount the first comic page in full-page mode. Without this the user sees the
    // raw EPUB rendering (page heading + figure) and pinch-zoom has no clone to act on.
    // Instant render (duration 0) — no entry animation on book open.
    const firstPage = this.#comicBookPages[0];
    if (firstPage) {
      this.#lastElementId = firstPage.comicImgId;
      firstPage.showFullPage(0);
    }

    if (typeof window.readium !== 'undefined') {
      // We need to capture scrollToId calls to handle scrolling to comic frames, but we want to preserve the original functionality for non-comic content. So we override scrollToId to route through our custom function, and keep a reference to the original function for non-comic use.
      window.readium.scrollToId = (id: string) => {
        this.scrollToId(id);
      };
    }

    window.addEventListener('resize', this.#onResize);
    this.#initGestureDetection();
  }

  public segmentDuration: number = 1000;

  readonly #comicBookPages: NotaComicBookPage[] = [];

  #lastElementId: string | null = null;

  #container!: HTMLDivElement;

  /**
   * True while narration is actively driving the comic (set by the first narration cue,
   * cleared by exitNarrationMode). When false, scrollToId shows the full page so the
   * user can explore freely before pressing play.
   */
  #narrationActive = false;
  /** True once a pinch gesture has been detected; remains true until clearManualOverride(). */
  #manualOverrideActive = false;
  /** True only while fingers are actively pinching (cleared on touchend). */
  #isPinching = false;
  #pinchStartDist = 0;
  #pinchStartW = 0;
  #pinchStartH = 0;
  #pinchStartScrollLeft = 0;
  #pinchStartScrollTop = 0;
  /** Focal point (midpoint of 2 fingers) in container-viewport coords at pinch start. */
  #focalX = 0;
  #focalY = 0;

  #getComicBookPageByFrameId(id: string): NotaComicBookPage | undefined {
    return this.#comicBookPages.find((page) => !!page.getComicArea(id));
  }

  get #activeClone(): HTMLImageElement | null {
    return this.#container.querySelector<HTMLImageElement>('img');
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
      // Id doesn't match a known comic frame on this page. Two cases:
      // 1. We're on a comic spine doc but Readium is scrolling to an unrelated anchor
      //    (e.g. the EPUB's heading "side2"). In explore mode the comic overlay is the
      //    canonical view — ignore the anchor and keep the overlay mounted.
      //    During narration this branch shouldn't fire (cues always target comic frames),
      //    but stay safe and also ignore it then.
      // 2. We're on a non-comic spine doc. #comicBookPages is empty, so fall through
      //    to native scroll behaviour and ensure the overlay (empty) is reset.
      if (this.#comicBookPages.length > 0) {
        return;
      }
      this.#container.classList.remove(activeComicPageContainerClass);
      for (let child of this.#container.childNodes) {
        this.#container.removeChild(child);
      }

      this.#originalScrollToIdFn.call(window.readium, id);
      return;
    }

    if (!this.#narrationActive) {
      page.showFullPage();
      return;
    }
    page.gotoComicFrame(lcId, duration ?? this.segmentDuration ?? 1000);
  }

  public gotoComicFrame(id: string, duration?: number) {
    this.scrollToId(id, duration);
  }

  /**
   * Called by native when narration stops. Clears the zoom layout and navigates back
   * to the full-page view so the user can browse freely. Does NOT replay any deferred
   * locator — that is Re-sync's job.
   */
  public exitNarrationMode(): void {
    this.#narrationActive = false;
    this.clearManualOverride();
    if (this.#lastElementId) {
      this.#getComicBookPageByFrameId(this.#lastElementId)?.showFullPage(0);
    }
  }

  /**
   * Called by native at the start of each narration cue (before scrollToId). Transitions
   * the comic from explore mode into narration-driven mode on the first cue. Any pre-play
   * manual zoom is cleared so narration can take over cleanly.
   */
  public onNarrationCue(): void {
    if (!this.#narrationActive) {
      this.#narrationActive = true;
      if (this.#manualOverrideActive) {
        this.clearManualOverride();
      }
    }
  }

  /**
   * Resets the manual-override flag and removes the zoom layout so the next narration
   * cue re-pans cleanly. Called by native before replaying the deferred locator on Re-sync.
   */
  public clearManualOverride(): void {
    this.#manualOverrideActive = false;
    this.#isPinching = false;
    const c = this.#container;
    c.classList.remove('nota-comic-manual');
    c.scrollLeft = 0;
    c.scrollTop = 0;
  }

  /**
   * Handles pinch-to-zoom (Plan A′): zoom by changing the clone's layout width/height
   * so the fixed container becomes scrollable, then let native overflow scroll handle
   * single-finger pan.
   *
   * All listeners are passive and on `document` (not captured on the container) so the
   * triptych pager's single-finger horizontal swipe is never blocked by JS.
   */
  #initGestureDetection(): void {
    document.addEventListener('touchstart', (e: TouchEvent) => {
      if (e.touches.length < 2) return;
      if (!this.#manualOverrideActive) {
        this.#enterManualZoom(e);
      } else {
        // Re-entering pinch while already in manual mode — update start state
        // so zoom continues from the current level (not from the original).
        this.#startPinch(e);
      }
    }, { passive: true });

    document.addEventListener('touchmove', (e: TouchEvent) => {
      if (e.touches.length >= 2 && this.#isPinching) {
        this.#onPinchMove(e);
      }
    }, { passive: true });

    document.addEventListener('touchend', () => {
      this.#isPinching = false;
    }, { passive: true });

    document.addEventListener('touchcancel', () => {
      this.#isPinching = false;
    }, { passive: true });
  }

  #pinchDist(e: TouchEvent): number {
    const dx = e.touches[1].clientX - e.touches[0].clientX;
    const dy = e.touches[1].clientY - e.touches[0].clientY;
    return Math.hypot(dx, dy);
  }

  /** Records pinch start state from current clone size + scroll position. */
  #startPinch(e: TouchEvent): void {
    const clone = this.#activeClone;
    if (!clone) return;
    this.#pinchStartDist = this.#pinchDist(e);
    this.#pinchStartW = parseFloat(clone.style.width) || 0;
    this.#pinchStartH = parseFloat(clone.style.height) || 0;
    this.#pinchStartScrollLeft = this.#container.scrollLeft;
    this.#pinchStartScrollTop = this.#container.scrollTop;
    const rect = this.#container.getBoundingClientRect();
    this.#focalX = ((e.touches[0].clientX + e.touches[1].clientX) / 2) - rect.left;
    this.#focalY = ((e.touches[0].clientY + e.touches[1].clientY) / 2) - rect.top;
    this.#isPinching = true;
  }

  /**
   * Called on the first 2-finger touch. Freezes the running animation at the current
   * visual frame, re-bases the clone to scroll coordinates, enters manual mode.
   */
  #enterManualZoom(e: TouchEvent): void {
    // Freeze animation and capture current frame geometry.
    const activePage = this.#lastElementId
      ? this.#getComicBookPageByFrameId(this.#lastElementId)
      : undefined;
    const frame = activePage?.freezeAtCurrentFrame();

    const clone = this.#activeClone;
    if (!clone) return;

    // Re-base: place the clone at (0,0) and set scroll to show the same viewport area.
    // The animation uses negative top/left to pan the large image; converting to scroll
    // lets the browser handle single-finger pan natively.
    if (frame) {
      const scrollLeft = Math.max(0, -frame.left);
      const scrollTop = Math.max(0, -frame.top);
      clone.style.left = '0px';
      clone.style.top = '0px';
      // Add class before setting scroll so the container accepts scrollLeft/Top writes.
      this.#container.classList.add('nota-comic-manual');
      this.#container.scrollLeft = scrollLeft;
      this.#container.scrollTop = scrollTop;
    } else {
      this.#container.classList.add('nota-comic-manual');
    }

    this.#manualOverrideActive = true;
    if (this.#narrationActive) {
      window.updateNarrationSync?.(false);
    }
    this.#startPinch(e);
  }

  /** Updates zoom on each pinch-move frame, keeping the focal point stationary. */
  #onPinchMove(e: TouchEvent): void {
    const clone = this.#activeClone;
    if (!clone || this.#pinchStartDist === 0 || this.#pinchStartW === 0) return;

    const ratio = this.#pinchDist(e) / this.#pinchStartDist;
    const containerW = this.#container.clientWidth;
    const containerH = this.#container.clientHeight;
    // Lower bound = fit image in viewport; upper bound = 4× original pinch-start size.
    const minW = Math.min(this.#pinchStartW, containerW);
    const maxW = this.#pinchStartW * 4;
    const newW = Math.max(minW, Math.min(maxW, this.#pinchStartW * ratio));
    const newH = newW * (this.#pinchStartH / this.#pinchStartW);

    clone.style.width = `${newW}px`;
    clone.style.height = `${newH}px`;

    // Zoom toward the focal point: the content point under focalX/Y should remain
    // at the same viewport position after the scale change.
    const newScrollLeft = (this.#pinchStartScrollLeft + this.#focalX) * (newW / this.#pinchStartW) - this.#focalX;
    const newScrollTop = (this.#pinchStartScrollTop + this.#focalY) * (newH / this.#pinchStartH) - this.#focalY;
    this.#container.scrollLeft = Math.max(0, Math.min(newW - containerW, newScrollLeft));
    this.#container.scrollTop = Math.max(0, Math.min(newH - containerH, newScrollTop));
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

  /**
   * Pauses the running animation at its current visual position and commits the live
   * frame geometry to inline styles. Returns the frozen geometry so the caller can
   * re-base it into scroll coordinates.
   *
   * Called by `NotaComicBook.#enterManualZoom` when a pinch gesture is detected.
   */
  public freezeAtCurrentFrame(): { top: number; left: number; width: number; height: number } {
    const img = this.#container.querySelector<HTMLImageElement>('img');
    // Read computed (animated) values before cancelling the animation.
    const cs = img ? getComputedStyle(img) : null;
    const frame = {
      top: parseFloat(cs?.top ?? '0'),
      left: parseFloat(cs?.left ?? '0'),
      width: parseFloat(cs?.width ?? '0'),
      height: parseFloat(cs?.height ?? '0'),
    };
    if (this.#animation) {
      try { this.#animation.commitStyles(); } catch { /* element may be detached */ }
      this.#animation.cancel();
      this.#animation = undefined;
    }
    // Write computed values as inline styles so they persist after animation teardown.
    if (img) {
      img.style.top = `${frame.top}px`;
      img.style.left = `${frame.left}px`;
      img.style.width = `${frame.width}px`;
      img.style.height = `${frame.height}px`;
      if (cs?.opacity) img.style.opacity = cs.opacity;
    }
    return frame;
  }

  /** Id of this page's comic image. Used by NotaComicBook to seed #lastElementId on auto-mount. */
  public get comicImgId(): string {
    return this.#comicImg.id;
  }

  /**
   * Renders the clone at the full-page view. Default duration animates smoothly for
   * narration→full transitions; pass 0 for an instant snap (initial mount, stop).
   */
  public showFullPage(duration: number = 400): void {
    this.renderCurrentFrame(this.#comicImg.id, duration);
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
