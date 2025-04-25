import animejs, { AnimeInstance } from 'animejs';
import { CanvasSize, ComicFrame } from 'types';
import { ComicBookCalc } from './ComicBookCalc';
import './ComicBookPage.scss';

const BLACK_AND_WHITE_MODE_KEY = 'black-and-white-rendering';

const blackAndWhiteCssClass = 'black-white';

export class ComicBookPage {
  constructor(w: Window) {
    this.window = w;

    const areaElements = this.getAreaElements();

    // TODO: Not sure this is the best way to detect if the page is a comic page.
    if (!areaElements?.length) {
      // Not a comic page.
      return;
    }

    const pageQuerySelector = 'body > div.page';
    const figureQuerySelector = 'body > figure';

    let container = this.document.querySelector<HTMLElement>(`${pageQuerySelector}, ${figureQuerySelector}`);

    let comicImg: HTMLImageElement;
    if (container?.nodeName.toLocaleLowerCase() === 'figure') {
      comicImg = this.document.querySelector(`${figureQuerySelector} > img`);
      comicImg.setAttribute('id', comicImg.id ?? container.id);

      container = this.renameElementName(figureQuerySelector, 'div');
      container.classList.add('page');

      // WORKAROUND: Hide all figures elements to make sure there is no duplicated images on the page.
      // TODO: remove this when this issue is solved: https://notalib.atlassian.net/browse/NOTA-9997
      for (const figureElement of this.document.querySelectorAll('figure')) {
        figureElement.setAttribute('style', 'display: none;');
      }
    } else if (!container || container.nodeName.toLocaleLowerCase() !== 'div') {
      // Image needs to be wrapped in a container that's not body
      comicImg = this.document.querySelector('body > img');
      container = this.document.createElement('div');
      container.classList.add('page');

      if (comicImg == null) {
        // No image found on the page.
        return;
      }

      comicImg.parentElement.insertBefore(container, comicImg);
      container.appendChild(comicImg);
    } else {
      comicImg = this.document.querySelector(`${pageQuerySelector} > img`);
    }

    this.comicImg = comicImg;
    this.container = container;
    this.canvasSize = this.extractCanvasSize();

    const canvasFrame = this.FullPageComicFrame;

    this.setComicArea(this.comicImg.id, canvasFrame);

    for (const area of areaElements) {
      const frame = this.extractComicFrame(area);
      this.setComicArea(area.id, frame);
    }

    if (comicImg == null) {
      return;
    }

    this.document.querySelector('body').classList.add('comicBody');

    this.window.addEventListener('resize', this.onResize);

    // Make sure whole comic image is visible on start.
    this.setCurrentFrame(this.comicImg.id, 0);
  }

  /**
   * Set comic area frame to the map, handle naming.
   *
   * @param id - id of the area
   * @param frame - frame of the area
   */
  protected setComicArea(id: string, frame: ComicFrame): void {
    id = id.toLocaleLowerCase();

    this.comicAreas.set(id, frame);
    this.comicAreas.set(`#${id}`, frame);
  }

  /**
   * Get comic area frame from the map, handle naming.
   *
   * @param id - id of the area
   */
  protected getComicArea(id: string): ComicFrame | undefined {
    id = id.toLocaleLowerCase();

    return this.comicAreas.get(id) ?? this.comicAreas.get(`#${id}`);
  }

  protected readonly window: Window;

  protected animeInstance?: AnimeInstance;

  protected get document(): Document {
    return this.window.document;
  }

  protected container: HTMLElement;

  protected get availableWidth(): number {
    return this.container.clientWidth;
  }

  protected get availableHeight(): number {
    return this.container.clientHeight;
  }

  protected readonly comicImg: HTMLImageElement;

  protected readonly comicAreas = new Map<string, ComicFrame>();

  protected currentFrame: ComicFrame;

  protected canvasSize: CanvasSize;

  protected duration: number;

  /**
   * Full page comic book frame
   */
  protected get FullPageComicFrame(): ComicFrame {
    return {
      ...this.canvasSize,
      left: 0,
      top: 0,
    };
  }

  /**
   * Render the comic book frame
   */
  protected renderCurrentComicFrame(): void {
    if (this.canvasSize == null || this.currentFrame == null || this.duration == null) {
      return;
    }

    // Remove old animation
    animejs.remove(this.comicImg);

    this.animeInstance = animejs({
      targets: this.comicImg,
      keyframes: ComicBookCalc.MakeKeyFrames(this.currentFrame, this.canvasSize, this.availableWidth, this.availableHeight, this.duration),
      easing: 'cubicBezier(0.455, 0.030, 0.515, 0.955)',
    });
  }

  public isComicBook(): boolean {
    try {
      return !!this.comicAreas.size;
    } catch (error) {
      return false;
    }
  }

  /**
   * Set current comic frame from id and duration
   */
  public setCurrentFrame(id: string, duration: number): void {
    const comicFrame = this.getComicArea(id);
    if (!comicFrame) {
      console.error(`setCurrentFrame(${id}) - not found`);
    }

    this.currentFrame = comicFrame;
    this.duration = duration;

    this.renderCurrentComicFrame();
  }

  /**
   * Set current comic frame to the image element.
   */
  public setCurrentImageFrame(): void {
    if (this.comicImg == null) {
      console.error('setCurrentImageFrame() - no comicImg');
      return;
    }

    this.setCurrentFrame(this.comicImg.id, 1000);
  }

  protected extractComicFrame(area: HTMLDivElement): ComicFrame {
    const frame: ComicFrame = {
      height: 0,
      width: 0,
      left: 0,
      top: 0,
    };

    for (const key of ['height', 'width', 'left', 'top']) {
      const value = area.style.getPropertyValue(key);
      if (!value) {
        console.error('{0} is missing style[{1}]', area.id, key);
        continue;
      }

      (frame as unknown as Record<string, number>)[key] = parseInt(value.replace(/px$/, ''), 10);
    }

    return frame;
  }

  protected extractCanvasSize(): CanvasSize {
    const dataKey = 'CanvasSize';

    if (this.comicImg.dataset[dataKey]) {
      return JSON.parse(this.comicImg.dataset[dataKey]) as CanvasSize;
    }

    const frame: CanvasSize = {
      height: 0,
      width: 0,
    };

    for (const key of ['height', 'width']) {
      const value = this.comicImg.style.getPropertyValue(key);
      if (!value) {
        console.error('{0} is missing style[{1}]', this.comicImg.id, key);
        continue;
      }

      (frame as unknown as Record<string, number>)[key] = parseInt(value.replace(/px$/, ''), 10);
    }

    this.comicImg.dataset[dataKey] = JSON.stringify(frame);

    return frame;
  }

  protected readonly onResize = (): void => this.renderCurrentComicFrame();

  private renameElementName(querySelector: string, tag: string): HTMLElement {
    const element = this.document.querySelector(querySelector);

    const newElement = document.createElement(tag);

    // move all elements in the other container.
    while (element.firstChild) {
      newElement.appendChild(element.firstChild);
    }

    element.parentNode.replaceChild(newElement, element);

    return newElement;
  }

  private getAreaElements() {
    return this.document.querySelectorAll<HTMLDivElement>('body > div.area, div.page > div.area, figure > div.area');
  }
}

declare global {
  interface Window {
    comicBookPage: ComicBookPage;
    GotoComicFrame: (id: string, duration: number) => void;
    SetBlackAndWhiteMode: (enable: boolean) => void;
    IsBlackAndWhiteEnabled: () => boolean;
  }
}

function Setup() {
  if (window.comicBookPage) {
    return;
  }

  window.SetBlackAndWhiteMode(window.IsBlackAndWhiteEnabled());

  document.removeEventListener('DOMContentLoaded', Setup);
  window.comicBookPage = new ComicBookPage(window);
}

window.GotoComicFrame = (id: string, duration: number) => {
  if (window.comicBookPage == null) {
    return;
  }

  const headingElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6');

  window.comicBookPage.setCurrentFrame(id, duration);

  document.querySelectorAll('.active').forEach((e) => e.classList.remove('active'));
  document.querySelector(`#${id.replace('#', '')}`)?.classList.add('active');

  const activeElement = document.querySelector('.active');
  if (activeElement.classList.contains('area') || activeElement?.tagName.toLowerCase() === 'img') {
    headingElements.forEach((e) => e.classList.add('hideHeading'));
  } else {
    headingElements.forEach((e) => e.classList.remove('hideHeading'));
    window.comicBookPage.setCurrentImageFrame();
  }
};

window.IsBlackAndWhiteEnabled = () => {
  return window.sessionStorage.getItem(BLACK_AND_WHITE_MODE_KEY) === 'true';
};

window.SetBlackAndWhiteMode = (enable: boolean) => {
  window.sessionStorage.setItem(BLACK_AND_WHITE_MODE_KEY, enable ? 'true' : 'false');

  if (enable) {
    document.body.classList.add(blackAndWhiteCssClass);
  } else {
    document.body.classList.remove(blackAndWhiteCssClass);
  }
};

if (document.readyState !== 'loading') {
  window.setTimeout(Setup);
} else {
  document.addEventListener('DOMContentLoaded', Setup);
}
