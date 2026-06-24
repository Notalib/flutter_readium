import {
  Link,
  Locator,
  LocatorLocations,
  Publication,
  ReadingProgression,
} from "@readium/shared";
import { ReadiumPublication, findLinkByHref } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { enrichWithTotalProgression } from "./locatorEnrich";

const log = createLogger("DivinaNav");

/**
 * Minimal, render-only navigator for the DiViNa (and CBZ) profile on web.
 *
 * ts-toolkit ships no DiViNa/image/fixed-layout navigator: `WebPubNavigator`
 * builds an HTML iframe per resource and throws on any non-HTML media type, so
 * image-based comics cannot render through it. This class fills that gap by
 * paging through the reading order's image resources one `<img>` at a time.
 *
 * Scope is deliberately render-only — there is no guided-navigation / sync
 * narration audio on web yet (that remains an iOS/Android-only feature). The
 * public method surface mirrors the subset of the upstream `VisualNavigator`
 * that `ReadiumReader` drives, so the reader can hold it interchangeably with
 * the EPUB / WebPub navigators.
 */
export class FlutterDivinaNavigator {
  /** Page positions (one per reading-order image). Exposed for `goToProgression`. */
  readonly positions: Locator[];

  private readonly _container: HTMLElement;
  private readonly _publication: ReadiumPublication;
  private readonly _baseURL: string;
  private readonly _items: Link[];
  private readonly _img: HTMLImageElement;
  private _index = 0;

  private static readonly TEXT_LOCATOR_DEBOUNCE_MS = 200;
  private _emitTimer: ReturnType<typeof setTimeout> | undefined;

  private constructor(
    container: HTMLElement,
    publication: ReadiumPublication,
    baseURL: string,
    positions: Locator[]
  ) {
    this._container = container;
    this._publication = publication;
    this._baseURL = baseURL;
    this._items = publication.manifest.readingOrder.items;
    this.positions = positions;
    this._img = FlutterDivinaNavigator._mountContainer(container);
  }

  static async create(
    container: HTMLElement,
    publication: ReadiumPublication,
    baseURL: string,
    initialPosition: Locator | undefined,
    _preferencesJsonString: string,
    setNav: (nav: FlutterDivinaNavigator) => void,
    setPositions?: (positions: Locator[]) => void
  ): Promise<FlutterDivinaNavigator> {
    log.info("Initializing DivinaNavigator");

    let positions = await publication.positionsFromManifest();
    if (positions.length === 0) {
      log.warn("No positions from manifest, falling back to readingOrder");
      positions = publication.manifest.readingOrder.items.map(
        (link: Link, index: number) =>
          new Locator({
            href: link.href,
            type: link.type ?? "image/jpeg",
            title: link.title,
            locations: new LocatorLocations({ position: index + 1 }),
          })
      );
    }

    const nav = new FlutterDivinaNavigator(
      container,
      publication,
      baseURL,
      positions
    );

    if (initialPosition) {
      const start = nav._indexForHref(initialPosition.href);
      if (start !== undefined) nav._index = start;
      else log.warn(`Initial locator href not found: ${initialPosition.href}`);
    }

    nav._render();
    setNav(nav);
    setPositions?.(positions);
    nav._emitCurrentLocator();

    log.info(`DivinaNavigator loaded (${nav._items.length} pages)`);
    return nav;
  }

  // ---------------------------------------------------------------------------
  // VisualNavigator-compatible surface (subset used by ReadiumReader)
  // ---------------------------------------------------------------------------

  get publication(): Publication {
    return this._publication;
  }

  get currentLocator(): Locator {
    return this._locatorForIndex(this._index);
  }

  goForward(_animated: boolean, cb: (ok: boolean) => void): void {
    cb(this._setIndex(this._index + 1));
  }

  goBackward(_animated: boolean, cb: (ok: boolean) => void): void {
    cb(this._setIndex(this._index - 1));
  }

  goRight(animated: boolean, cb: (ok: boolean) => void): void {
    this._isRTL() ? this.goBackward(animated, cb) : this.goForward(animated, cb);
  }

  goLeft(animated: boolean, cb: (ok: boolean) => void): void {
    this._isRTL() ? this.goForward(animated, cb) : this.goBackward(animated, cb);
  }

  go(locator: Locator, _animated: boolean, cb: (ok: boolean) => void): void {
    const index = this._indexForHref(locator.href);
    if (index === undefined) {
      log.warn(`go: no page for href ${locator.href}`);
      cb(false);
      return;
    }
    cb(this._setIndex(index));
  }

  goLink(link: Link, _animated: boolean, cb: (ok: boolean) => void): void {
    const index = this._indexForHref(link.href);
    if (index === undefined) {
      log.warn(`goLink: no page for href ${link.href}`);
      cb(false);
      return;
    }
    cb(this._setIndex(index));
  }

  async destroy(): Promise<void> {
    if (this._emitTimer !== undefined) clearTimeout(this._emitTimer);
    this._emitTimer = undefined;
    this._container.innerHTML = "";
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /** Resets `container` to a centered, letterboxed image stage and returns the `<img>`. */
  private static _mountContainer(container: HTMLElement): HTMLImageElement {
    container.innerHTML = "";
    container.style.display = "flex";
    container.style.alignItems = "center";
    container.style.justifyContent = "center";
    container.style.width = "100%";
    container.style.height = "100%";
    container.style.overflow = "hidden";
    container.style.background = "#000";

    const img = document.createElement("img");
    img.style.maxWidth = "100%";
    img.style.maxHeight = "100%";
    img.style.objectFit = "contain";
    img.alt = "";
    container.appendChild(img);
    return img;
  }

  private _isRTL(): boolean {
    return (
      this._publication.metadata.readingProgression === ReadingProgression.rtl
    );
  }

  private _indexForHref(href: string): number | undefined {
    const link = findLinkByHref(this._items, href);
    if (!link) return undefined;
    const index = this._items.indexOf(link);
    return index === -1 ? undefined : index;
  }

  /** Navigates to `index` if in range; returns whether it became the current page. */
  private _setIndex(index: number): boolean {
    if (index < 0 || index >= this._items.length) return false;
    if (index === this._index) return true;
    this._index = index;
    this._render();
    this._emitCurrentLocator();
    return true;
  }

  private _render(): void {
    const link = this._items[this._index];
    const url = link?.toURL(this._baseURL);
    if (!url) {
      log.error(`Cannot resolve URL for page ${this._index}: ${link?.href}`);
      return;
    }
    this._img.onerror = () =>
      log.error(`Failed to load page ${this._index}: ${url}`);
    this._img.src = url;
  }

  private _locatorForIndex(index: number): Locator {
    const base =
      this.positions[index] ??
      new Locator({
        href: this._items[index]?.href ?? "",
        type: this._items[index]?.type ?? "image/jpeg",
        locations: new LocatorLocations({ position: index + 1 }),
      });
    return enrichWithTotalProgression(base, this.positions.length);
  }

  private _emitCurrentLocator(): void {
    if (this._emitTimer !== undefined) clearTimeout(this._emitTimer);
    const locator = this._locatorForIndex(this._index);
    this._emitTimer = setTimeout(() => {
      this._emitTimer = undefined;
      window.updateTextLocator?.(JSON.stringify(locator.serialize()));
    }, FlutterDivinaNavigator.TEXT_LOCATOR_DEBOUNCE_MS);
  }
}
