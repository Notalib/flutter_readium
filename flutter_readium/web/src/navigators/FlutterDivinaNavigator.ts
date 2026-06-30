import {
  Link,
  Locator,
  LocatorLocations,
  Publication,
  ReadingProgression,
} from "@readium/shared";
import { ReadiumPublication, findLinkByHref } from "../utils/ReadiumExtensions";
import { ComicRegion } from "../mediaoverlay/syncNarration";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { enrichWithTotalProgression } from "./locatorEnrich";
import {
  ComicTransform,
  IDENTITY,
  clampTransform,
  decayVelocity,
  overscrollTransform,
  regionToTransform,
} from "./comicTransform";
import { shouldAutoPan } from "./comicAutoPan";

const log = createLogger("DivinaNav");

/** Double-tap zoom level and the window (ms) within which two taps count as one. */
const DOUBLE_TAP_SCALE = 2.5;
const DOUBLE_TAP_MS = 300;
/** Driven-pan animation duration (audio-synced panel framing). */
const PAN_ANIM_MS = 280;
/** Kinetic-pan (fling) tuning — all px/ms unless noted. */
const FLING_MIN_SPEED = 0.05; // release faster than this → momentum
const MOMENTUM_MIN_SPEED = 0.015; // below this → stop and settle
const MOMENTUM_FRICTION = 0.005; // exponential decay rate per ms

/**
 * Minimal, render-only navigator for the DiViNa (and CBZ) profile on web, with
 * manual zoom/pan and audio-driven panel pan.
 *
 * ts-toolkit ships no DiViNa/image/fixed-layout navigator, so this class pages
 * through the reading order's image resources one `<img>` at a time. Zoom/pan is
 * a CSS-transform layer over the image (geometry in {@link ./comicTransform}):
 * the page edge clamps (no rubber-band, matching the "platform-native edge"
 * decision for web). Audio narration can drive the view to the panel being read
 * via {@link panToRegion}; a manual gesture takes over (`_manuallyOverridden`)
 * until the next page turn, gated by {@link shouldAutoPan}.
 *
 * The public method surface mirrors the subset of the upstream `VisualNavigator`
 * that `ReadiumReader` drives, so the reader can hold it interchangeably with the
 * EPUB / WebPub navigators.
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

  // Zoom/pan state.
  private _transform: ComicTransform = IDENTITY;
  private _natW = 0;
  private _natH = 0;
  private _autoPanEnabled = true;
  private _manuallyOverridden = false;
  private _lastRegion: ComicRegion | null = null;
  // Set when a region pan was requested before the page image was measured
  // (natW/natH still 0). The <img> `load` handler applies the pan to _lastRegion
  // once natural dimensions are known, so the first cue on a freshly-loaded page
  // isn't dropped (it would otherwise wait for the next cue to re-frame).
  private _pendingRegionPan = false;

  // Gesture tracking (Pointer Events).
  private readonly _pointers = new Map<number, { x: number; y: number }>();
  private _pinchStartDist = 0;
  private _pinchStartScale = 1;
  private _lastTapTime = 0;
  private _lastTapX = 0;
  private _lastTapY = 0;
  // Drag-pan anchor: the pointer position and transform at the start of a pan,
  // so the live translate is computed absolutely (no drift when overscroll
  // damping kicks in). Null when not panning.
  private _panAnchor: { x: number; y: number; tx: number; ty: number } | null = null;
  // Velocity sampling for kinetic (fling) panning, and the active rAF handle.
  private _velX = 0;
  private _velY = 0;
  private _lastMoveT = 0;
  private _lastMoveX = 0;
  private _lastMoveY = 0;
  private _momentumRAF: number | undefined;

  private static readonly TEXT_LOCATOR_DEBOUNCE_MS = 200;
  private _emitTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly _onResize = () => this._layout(true);

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
    this._img = this._mountContainer(container);
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
    log.info(
      "Initializing DivinaNavigator",
      initialPosition ? `from ${initialPosition.href}` : "(no initial position)"
    );

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

    log.info(`DivinaNavigator loaded (${nav._items.length} pages, ${positions.length} positions)`);
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
    log.debug(`go: ${locator.href} -> page ${index + 1}`);
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
    log.info("Destroying DivinaNavigator");
    this._stopMomentum();
    if (this._emitTimer !== undefined) clearTimeout(this._emitTimer);
    this._emitTimer = undefined;
    window.removeEventListener("resize", this._onResize);
    this._container.innerHTML = "";
  }

  // ---------------------------------------------------------------------------
  // Comic zoom/pan API (called by ReadiumReader on the concrete type)
  // ---------------------------------------------------------------------------

  /**
   * Enable/disable audio-driven panel auto-pan (the `setNarrationSyncEnabled` toggle).
   * Calling with `true` also clears any manual override and immediately re-pans
   * to the last narration region — so this doubles as the "Re-sync" action.
   */
  setAutoPan(enabled: boolean): void {
    this._autoPanEnabled = enabled;
    log.debug(`setAutoPan(${enabled})`);
    if (enabled && this._manuallyOverridden) {
      this._manuallyOverridden = false;
      this.panToRegion(this._lastRegion);
      window.updateNarrationSync?.(true);
    }
  }

  /**
   * Audio-driven pan to a narration cue's panel region (or fit-whole-page when
   * null). No-ops when auto-pan is disabled or the user has taken manual control
   * of the current page.
   */
  panToRegion(region: ComicRegion | null): void {
    this._lastRegion = region;
    if (!shouldAutoPan({
      autoPanEnabled: this._autoPanEnabled,
      manuallyOverridden: this._manuallyOverridden,
    })) {
      log.debug(
        "panToRegion skipped",
        this._autoPanEnabled ? "manual override active" : "auto-pan disabled"
      );
      return;
    }
    if (this._natW === 0 || this._natH === 0) {
      this._pendingRegionPan = true;
      log.debug("panToRegion deferred: image not measured yet");
      return;
    }
    this._pendingRegionPan = false;
    log.debug(
      region
        ? `panToRegion x=${region.x} y=${region.y} w=${region.w} h=${region.h}`
        : "panToRegion full page"
    );
    const { vw, vh } = this._viewport();
    const target = regionToTransform(this._natW, this._natH, region, vw, vh);
    this._applyTransform(target, true);
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  /** Resets `container` to a letterboxed image stage and returns the `<img>`. */
  private _mountContainer(container: HTMLElement): HTMLImageElement {
    container.innerHTML = "";
    container.style.position = "relative";
    container.style.width = "100%";
    container.style.height = "100%";
    container.style.overflow = "hidden";
    container.style.background = "#000";
    container.style.touchAction = "none"; // we handle pinch/pan ourselves

    const img = document.createElement("img");
    // Base display: fill the container and let the browser contain-fit the page.
    // This guarantees the un-zoomed page is always fully visible (letterboxed),
    // independent of natural size / viewport. Zoom/pan is layered on top as a
    // center-origin CSS transform (see comicTransform.ts).
    img.style.position = "absolute";
    img.style.left = "0";
    img.style.top = "0";
    img.style.width = "100%";
    img.style.height = "100%";
    img.style.objectFit = "contain";
    img.style.transformOrigin = "center center";
    img.style.willChange = "transform";
    img.draggable = false;
    img.alt = "";
    img.addEventListener("load", () => {
      this._natW = img.naturalWidth;
      this._natH = img.naturalHeight;
      if (this._pendingRegionPan) {
        // A narration cue requested a panel pan before the image was measured;
        // apply it now that natural dimensions are known (panToRegion clears the flag).
        this.panToRegion(this._lastRegion);
      } else {
        // Re-apply current zoom (identity on a fresh page) now that we know the size.
        this._applyTransform(this._transform, false);
      }
    });
    container.appendChild(img);

    this._attachGestureListeners(container);
    window.addEventListener("resize", this._onResize);
    return img;
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
    // Reset measured size; the load handler re-measures and re-lays out.
    this._natW = 0;
    this._natH = 0;
    log.debug(`render page ${this._index + 1}/${this._items.length}: ${link.href}`);
    this._img.src = url;
  }

  private _viewport(): { vw: number; vh: number } {
    return {
      vw: this._container.clientWidth,
      vh: this._container.clientHeight,
    };
  }

  /**
   * Re-applies the transform after a viewport change. The base contain-fit is
   * handled by CSS `object-fit`, so there is no per-page sizing to do here — on
   * resize we just reset to the fitted page (transform px are viewport-relative).
   */
  private _layout(resetZoom: boolean): void {
    this._applyTransform(resetZoom ? IDENTITY : this._transform, false);
  }

  /**
   * Applies a transform. `soft` (live drag) allows damped overshoot past the
   * edges via {@link overscrollTransform}; otherwise it hard-{@link clampTransform}s.
   * A non-soft animated apply is the spring-back "settle" on release.
   */
  private _applyTransform(t: ComicTransform, animate: boolean, soft = false): void {
    const { vw, vh } = this._viewport();
    const resolved = soft
      ? overscrollTransform(t, this._natW, this._natH, vw, vh)
      : clampTransform(t, this._natW, this._natH, vw, vh);
    this._transform = resolved;
    this._img.style.transition = animate
      ? `transform ${PAN_ANIM_MS}ms ease-out`
      : "none";
    this._img.style.transform =
      `translate(${resolved.tx}px, ${resolved.ty}px) scale(${resolved.scale})`;
  }

  // ---------------------------------------------------------------------------
  // Manual gestures (pinch / drag-pan / double-tap / wheel)
  // ---------------------------------------------------------------------------

  private _attachGestureListeners(el: HTMLElement): void {
    el.addEventListener("pointerdown", (e) => this._onPointerDown(e));
    el.addEventListener("pointermove", (e) => this._onPointerMove(e));
    el.addEventListener("pointerup", (e) => this._onPointerUp(e));
    el.addEventListener("pointercancel", (e) => this._onPointerUp(e));
    el.addEventListener("wheel", (e) => this._onWheel(e), { passive: false });
  }

  /** Marks the current page as user-controlled, suspending auto-pan until page turn. */
  private _markManual(): void {
    if (!this._manuallyOverridden) {
      this._manuallyOverridden = true;
      window.updateNarrationSync?.(false);
    }
  }

  private _onPointerDown(e: PointerEvent): void {
    this._stopMomentum(); // a new touch cancels any ongoing fling
    this._container.setPointerCapture?.(e.pointerId);
    this._pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (this._pointers.size === 2) {
      const [a, b] = [...this._pointers.values()];
      this._pinchStartDist = Math.hypot(a.x - b.x, a.y - b.y) || 1;
      this._pinchStartScale = this._transform.scale;
      this._panAnchor = null; // a pinch supersedes panning
    } else if (this._pointers.size === 1) {
      this._anchorPanTo(e.clientX, e.clientY);
    }
  }

  private _onPointerMove(e: PointerEvent): void {
    if (!this._pointers.has(e.pointerId)) return;
    this._pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

    if (this._pointers.size >= 2) {
      // Pinch zoom about the midpoint of the two active pointers.
      const [a, b] = [...this._pointers.values()];
      const dist = Math.hypot(a.x - b.x, a.y - b.y) || 1;
      const midX = (a.x + b.x) / 2;
      const midY = (a.y + b.y) / 2;
      const targetScale =
        (dist / this._pinchStartDist) * this._pinchStartScale;
      this._zoomAbout(midX, midY, targetScale);
      this._markManual();
    } else if (this._panAnchor && this._transform.scale > 1) {
      // Single-pointer drag-pan (only meaningful when zoomed in). Computed
      // absolutely from the anchor so overscroll damping doesn't cause drift.
      this._sampleVelocity(e.clientX, e.clientY);
      const tx = this._panAnchor.tx + (e.clientX - this._panAnchor.x);
      const ty = this._panAnchor.ty + (e.clientY - this._panAnchor.y);
      this._applyTransform({ scale: this._transform.scale, tx, ty }, false, true);
      this._markManual();
    }
  }

  private _onPointerUp(e: PointerEvent): void {
    this._container.releasePointerCapture?.(e.pointerId);
    this._pointers.delete(e.pointerId);

    if (this._pointers.size === 1) {
      // Pinch ended with one finger left → hand off to panning from here.
      const [id] = [...this._pointers.keys()];
      const p = this._pointers.get(id)!;
      this._anchorPanTo(p.x, p.y);
      return;
    }
    if (this._pointers.size > 0) return;

    // All released. Double-tap toggle-zoom takes priority over settle.
    this._panAnchor = null;
    const now = performance.now();
    const dt = now - this._lastTapTime;
    const moved = Math.hypot(e.clientX - this._lastTapX, e.clientY - this._lastTapY);
    if (dt < DOUBLE_TAP_MS && moved < 24) {
      this._toggleZoomAt(e.clientX, e.clientY);
      this._lastTapTime = 0;
      return;
    }
    this._lastTapTime = now;
    this._lastTapX = e.clientX;
    this._lastTapY = e.clientY;
    // Fling: a fast release glides on with momentum; otherwise spring back into
    // bounds (animated hard-clamp — a no-op when already inside).
    if (this._transform.scale > 1 && Math.hypot(this._velX, this._velY) >= FLING_MIN_SPEED) {
      this._startMomentum();
    } else {
      this._applyTransform(this._transform, true, false);
    }
  }

  /** Records the pan anchor (pointer + transform) and resets velocity sampling. */
  private _anchorPanTo(x: number, y: number): void {
    this._panAnchor = { x, y, tx: this._transform.tx, ty: this._transform.ty };
    this._velX = 0;
    this._velY = 0;
    this._lastMoveT = performance.now();
    this._lastMoveX = x;
    this._lastMoveY = y;
  }

  /** Smooths the pointer velocity (px/ms) from the latest drag sample. */
  private _sampleVelocity(x: number, y: number): void {
    const now = performance.now();
    const dt = now - this._lastMoveT;
    if (dt > 0 && dt < 200) {
      const instVX = (x - this._lastMoveX) / dt;
      const instVY = (y - this._lastMoveY) / dt;
      this._velX = 0.6 * this._velX + 0.4 * instVX;
      this._velY = 0.6 * this._velY + 0.4 * instVY;
    }
    this._lastMoveT = now;
    this._lastMoveX = x;
    this._lastMoveY = y;
  }

  /**
   * Kinetic-pan loop: glides the raw position by the release velocity,
   * decelerating each frame (and bleeding velocity faster past the edges), then
   * springs back into bounds when it slows below {@link MOMENTUM_MIN_SPEED}.
   */
  private _startMomentum(): void {
    this._stopMomentum();
    let last = performance.now();
    let tx = this._transform.tx;
    let ty = this._transform.ty;
    const scale = this._transform.scale;
    const step = (now: number) => {
      const dt = Math.min(32, now - last); // clamp dt to avoid post-stall jumps
      last = now;
      tx += this._velX * dt;
      ty += this._velY * dt;
      const decayed = decayVelocity({ vx: this._velX, vy: this._velY }, dt, MOMENTUM_FRICTION);
      this._velX = decayed.vx;
      this._velY = decayed.vy;
      this._applyTransform({ scale, tx, ty }, false, true); // paint (damped past edge)

      const { vw, vh } = this._viewport();
      const clamped = clampTransform({ scale, tx, ty }, this._natW, this._natH, vw, vh);
      const overshot =
        Math.abs(clamped.tx - tx) > 0.5 || Math.abs(clamped.ty - ty) > 0.5;
      if (overshot || Math.hypot(this._velX, this._velY) < MOMENTUM_MIN_SPEED) {
        // Hit an edge (or out of speed): drop velocity and spring straight back
        // on the next frame — no lingering at the overshoot.
        this._velX = 0;
        this._velY = 0;
        this._momentumRAF = requestAnimationFrame(() => {
          this._momentumRAF = undefined;
          this._applyTransform(this._transform, true, false);
        });
        return;
      }
      this._momentumRAF = requestAnimationFrame(step);
    };
    this._momentumRAF = requestAnimationFrame(step);
  }

  private _stopMomentum(): void {
    if (this._momentumRAF !== undefined) {
      cancelAnimationFrame(this._momentumRAF);
      this._momentumRAF = undefined;
    }
  }

  private _onWheel(e: WheelEvent): void {
    e.preventDefault();
    const factor = Math.exp(-e.deltaY / 300); // smooth multiplicative zoom
    this._zoomAbout(e.clientX, e.clientY, this._transform.scale * factor);
    this._markManual();
  }

  /**
   * Zoom to `targetScale` keeping the viewport point (clientX, clientY) fixed.
   * Center-origin model: with O = container center and current (s, t),
   * `t' = (P - O)(1 - s'/s) + t·(s'/s)` keeps P fixed.
   */
  private _zoomAbout(clientX: number, clientY: number, targetScale: number, animate = false): void {
    const rect = this._container.getBoundingClientRect();
    const px = clientX - rect.left - rect.width / 2; // P - O
    const py = clientY - rect.top - rect.height / 2;
    const s0 = this._transform.scale;
    const s = Math.max(1, targetScale);
    const r = s / s0;
    const tx = px * (1 - r) + this._transform.tx * r;
    const ty = py * (1 - r) + this._transform.ty * r;
    this._applyTransform({ scale: s, tx, ty }, animate);
  }

  private _toggleZoomAt(clientX: number, clientY: number): void {
    this._markManual();
    if (this._transform.scale > 1.01) {
      this._applyTransform(IDENTITY, true);
    } else {
      this._zoomAbout(clientX, clientY, DOUBLE_TAP_SCALE, true);
    }
  }

  // ---------------------------------------------------------------------------
  // Page model
  // ---------------------------------------------------------------------------

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
    log.debug(`page changed to ${index + 1}/${this._items.length}: ${this._items[index]?.href ?? "(unknown)"}`);
    // New page → drop manual override so auto-pan re-engages, reset zoom.
    this._stopMomentum();
    this._panAnchor = null;
    if (this._manuallyOverridden) {
      this._manuallyOverridden = false;
      window.updateNarrationSync?.(true);
    }
    this._transform = IDENTITY;
    // A pan deferred for the previous page's image is stale now.
    this._pendingRegionPan = false;
    this._render();
    this._emitCurrentLocator();
    return true;
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
