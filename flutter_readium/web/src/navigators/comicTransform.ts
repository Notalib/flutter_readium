/**
 * Pure geometry for comic zoom/pan on web. Kept free of DOM so it can be unit
 * tested and so the iOS/Android native ports have an exact reference spec.
 *
 * Coordinate model: the page `<img>` fills the container and uses CSS
 * `object-fit: contain` (so the base, un-zoomed page is ALWAYS fully visible —
 * letterboxed — regardless of natural size or viewport). The contained image
 * occupies {@link fitRect} within the container. A {@link ComicTransform} is
 * applied on top as `translate(tx px, ty px) scale(scale)` with the default
 * `transform-origin: center` (the container center `O = (vw/2, vh/2)`):
 *
 *   final(p) = O + scale * (p - O) + (tx, ty)
 *
 * so a viewport point `p` maps to `final(p)`. The identity transform shows the
 * full contain-fitted page.
 */
import { ComicRegion } from "../mediaoverlay/syncNarration";

export interface ComicTransform {
  scale: number;
  /** Translation in viewport pixels (applied with transform-origin: center). */
  tx: number;
  ty: number;
}

export interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** The identity transform (full page, contain-fit, no pan). */
export const IDENTITY: ComicTransform = { scale: 1, tx: 0, ty: 0 };

/**
 * Contain-fit of a `natW x natH` image centered in a `vw x vh` viewport — the
 * rect the `object-fit: contain` image occupies at scale 1.
 */
export function fitRect(
  natW: number,
  natH: number,
  vw: number,
  vh: number
): Rect {
  if (natW <= 0 || natH <= 0) return { left: 0, top: 0, width: vw, height: vh };
  const k = Math.min(vw / natW, vh / natH);
  const width = natW * k;
  const height = natH * k;
  return { left: (vw - width) / 2, top: (vh - height) / 2, width, height };
}

/**
 * Transform that frames `region` (source-image pixels) centered and filling the
 * viewport. A `null` region returns {@link IDENTITY} (whole page, contain). An
 * optional `padding` (0–0.49) leaves margin around the region.
 */
export function regionToTransform(
  natW: number,
  natH: number,
  region: ComicRegion | null,
  vw: number,
  vh: number,
  padding = 0
): ComicTransform {
  if (!region || natW <= 0 || natH <= 0) return IDENTITY;
  const base = fitRect(natW, natH, vw, vh);
  const k = base.width / natW; // == base.height / natH (aspect preserved)

  // Displayed size of the region at scale 1, then the scale to fit the viewport.
  const regionDispW = region.w * k;
  const regionDispH = region.h * k;
  const pad = 1 - 2 * Math.max(0, Math.min(0.49, padding));
  const scale = Math.min((vw * pad) / regionDispW, (vh * pad) / regionDispH);

  // Region center in container coords, then translate it to the viewport center
  // (transform-origin is the center O, so t = -scale * (P* - O)).
  const pStarX = base.left + (region.x + region.w / 2) * k;
  const pStarY = base.top + (region.y + region.h / 2) * k;
  const tx = -scale * (pStarX - vw / 2);
  const ty = -scale * (pStarY - vh / 2);
  return { scale, tx, ty };
}

/**
 * Clamps a transform so the scaled image never overscrolls: when larger than
 * the viewport along an axis it stays edge-to-edge; when smaller it is centered.
 * Scale is floored at 1 (never below page-fit). No rubber-band (web = clamp).
 */
export function clampTransform(
  t: ComicTransform,
  natW: number,
  natH: number,
  vw: number,
  vh: number
): ComicTransform {
  const scale = Math.max(1, t.scale);
  const base = fitRect(natW, natH, vw, vh);
  const effW = base.width * scale;
  const effH = base.height * scale;

  // Rendered content start (top-left) on an axis = originTerm + translate,
  // where originTerm folds in the center-origin scaling of the base rect.
  const clampAxis = (
    translate: number,
    baseStart: number,
    viewportCenter: number,
    eff: number,
    viewport: number
  ): number => {
    const originTerm = viewportCenter + scale * (baseStart - viewportCenter);
    const start = originTerm + translate;
    const clampedStart =
      eff <= viewport
        ? (viewport - eff) / 2 // smaller than viewport → center
        : Math.min(0, Math.max(viewport - eff, start)); // larger → no gap
    return clampedStart - originTerm;
  };

  return {
    scale,
    tx: clampAxis(t.tx, base.left, vw / 2, effW, vw),
    ty: clampAxis(t.ty, base.top, vh / 2, effH, vh),
  };
}

export interface Velocity {
  /** Pixels per millisecond. */
  vx: number;
  vy: number;
}

/**
 * Framerate-independent exponential velocity decay for kinetic (fling) panning.
 * `perMs` is the decay rate (larger = stops sooner). Pure, so the deceleration
 * curve is unit-tested and the native ports can match it.
 */
export function decayVelocity(v: Velocity, dtMs: number, perMs = 0.005): Velocity {
  const f = Math.exp(-perMs * Math.max(0, dtMs));
  return { vx: v.vx * f, vy: v.vy * f };
}

/**
 * iOS-style rubber-band resistance. Maps an overshoot `excess` (px past the
 * edge) to a damped, smaller distance that asymptotes toward `dim`, so the
 * further you pull the more it resists. `c` is the resistance constant (the
 * UIScrollView default is 0.55).
 */
export function rubberband(excess: number, dim: number, c = 0.55): number {
  if (excess <= 0 || dim <= 0) return 0;
  return (1 - 1 / ((excess * c) / dim + 1)) * dim;
}

/**
 * Like {@link clampTransform} but allows *damped* overshoot past the edges —
 * for the live drag, so the page can be pulled slightly past its bounds and
 * springs back (via an animated {@link clampTransform}) on release. Scale is
 * still floored at 1 (no scale bounce during pan).
 */
export function overscrollTransform(
  t: ComicTransform,
  natW: number,
  natH: number,
  vw: number,
  vh: number
): ComicTransform {
  const scale = Math.max(1, t.scale);
  const base = fitRect(natW, natH, vw, vh);
  const effW = base.width * scale;
  const effH = base.height * scale;

  const axis = (
    translate: number,
    baseStart: number,
    viewportCenter: number,
    eff: number,
    viewport: number
  ): number => {
    const originTerm = viewportCenter + scale * (baseStart - viewportCenter);
    const desired = originTerm + translate;
    const lo = eff <= viewport ? (viewport - eff) / 2 : viewport - eff;
    const hi = eff <= viewport ? (viewport - eff) / 2 : 0;
    let start: number;
    if (desired > hi) start = hi + rubberband(desired - hi, viewport);
    else if (desired < lo) start = lo - rubberband(lo - desired, viewport);
    else start = desired;
    return start - originTerm;
  };

  return {
    scale,
    tx: axis(t.tx, base.left, vw / 2, effW, vw),
    ty: axis(t.ty, base.top, vh / 2, effH, vh),
  };
}
