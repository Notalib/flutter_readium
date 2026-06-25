/**
 * Unit tests for the pure comic zoom/pan geometry (comicTransform.ts).
 */

import {
  IDENTITY,
  fitRect,
  regionToTransform,
  clampTransform,
  rubberband,
  overscrollTransform,
  decayVelocity,
} from "../navigators/comicTransform";

describe("fitRect", () => {
  it("centers a landscape image letterboxed top/bottom in a square viewport", () => {
    // 200x100 into 100x100 → k=0.5 → 100x50, centered vertically.
    expect(fitRect(200, 100, 100, 100)).toEqual({
      left: 0,
      top: 25,
      width: 100,
      height: 50,
    });
  });

  it("falls back to the full viewport for a degenerate image size", () => {
    expect(fitRect(0, 0, 100, 80)).toEqual({
      left: 0,
      top: 0,
      width: 100,
      height: 80,
    });
  });
});

describe("regionToTransform", () => {
  it("returns identity for a null region (whole page, fit)", () => {
    expect(regionToTransform(1000, 2000, null, 400, 800)).toEqual(IDENTITY);
  });

  it("centers and fills a panel region", () => {
    // Image 1000x1000 fit into 500x500 → k=0.5, base at (0,0,500,500).
    // Region 250x250 at (250,250); its center is (375,375).
    const t = regionToTransform(1000, 1000, { x: 250, y: 250, w: 250, h: 250 }, 500, 500);
    // Region displayed = 250*0.5 = 125 px; scale to fill 500 → 4x.
    expect(t.scale).toBeCloseTo(4, 5);
    // Center-origin: P* = base.left + cx*k = 0 + 375*0.5 = 187.5; O = 250.
    // tx = -scale*(P* - O) = -4*(187.5 - 250) = 250.
    expect(t.tx).toBeCloseTo(250, 5);
    expect(t.ty).toBeCloseTo(250, 5);
  });

  it("picks the limiting axis for a non-square region", () => {
    // Wide region: width should be the limiting dimension.
    const t = regionToTransform(1000, 1000, { x: 0, y: 0, w: 500, h: 100 }, 500, 500);
    // regionDisp = 250 x 50; scale = min(500/250, 500/50) = min(2,10) = 2.
    expect(t.scale).toBeCloseTo(2, 5);
  });

  it("honors padding (zooms in less)", () => {
    const tight = regionToTransform(1000, 1000, { x: 0, y: 0, w: 250, h: 250 }, 500, 500);
    const padded = regionToTransform(1000, 1000, { x: 0, y: 0, w: 250, h: 250 }, 500, 500, 0.1);
    expect(padded.scale).toBeLessThan(tight.scale);
  });
});

describe("clampTransform", () => {
  it("floors scale at page-fit (never below 1) and centers", () => {
    const t = clampTransform({ scale: 0.5, tx: 0, ty: 0 }, 1000, 1000, 500, 500);
    expect(t.scale).toBe(1);
    expect(t.tx).toBeCloseTo(0, 5);
    expect(t.ty).toBeCloseTo(0, 5);
  });

  it("prevents overscroll past the left/top edge when zoomed in", () => {
    // base 500x500 at (0,0); scale 2 → eff 1000. originTerm = 250 + 2*(0-250) = -250.
    // Huge +tx would push content start > 0 (gap); clamp content start to 0 → tx = 250.
    const t = clampTransform({ scale: 2, tx: 9999, ty: 9999 }, 1000, 1000, 500, 500);
    expect(t.tx).toBeCloseTo(250, 5);
    expect(t.ty).toBeCloseTo(250, 5);
  });

  it("prevents overscroll past the right/bottom edge", () => {
    // Content start clamped to viewport - eff = 500 - 1000 = -500 → tx = -500 - (-250) = -250.
    const t = clampTransform({ scale: 2, tx: -9999, ty: -9999 }, 1000, 1000, 500, 500);
    expect(t.tx).toBeCloseTo(-250, 5);
    expect(t.ty).toBeCloseTo(-250, 5);
  });
});

describe("rubberband", () => {
  it("is zero at (or below) the edge", () => {
    expect(rubberband(0, 500)).toBe(0);
    expect(rubberband(-10, 500)).toBe(0);
  });

  it("damps overshoot (output smaller than input) and is monotonic", () => {
    expect(rubberband(100, 500)).toBeLessThan(100);
    expect(rubberband(200, 500)).toBeGreaterThan(rubberband(100, 500));
  });

  it("asymptotes toward dim, never exceeding it", () => {
    expect(rubberband(1e6, 500)).toBeLessThan(500);
  });
});

describe("overscrollTransform", () => {
  it("leaves an in-bounds transform unchanged", () => {
    // scale 2, base 500 at left 0 → content-start range [-500,0]; tx=100 → start -150 (in range).
    const t = overscrollTransform({ scale: 2, tx: 100, ty: 100 }, 1000, 1000, 500, 500);
    expect(t.tx).toBeCloseTo(100, 5);
    expect(t.ty).toBeCloseTo(100, 5);
  });

  it("allows damped overshoot past the clamp bound", () => {
    const clamped = clampTransform({ scale: 2, tx: 400, ty: 0 }, 1000, 1000, 500, 500);
    const soft = overscrollTransform({ scale: 2, tx: 400, ty: 0 }, 1000, 1000, 500, 500);
    // Past the clamp (250) but damped below the raw request (400).
    expect(soft.tx).toBeGreaterThan(clamped.tx);
    expect(soft.tx).toBeLessThan(400);
  });

  it("floors scale at 1 like clamp", () => {
    expect(overscrollTransform({ scale: 0.4, tx: 0, ty: 0 }, 1000, 1000, 500, 500).scale).toBe(1);
  });
});

describe("decayVelocity", () => {
  it("leaves velocity unchanged for zero elapsed time", () => {
    expect(decayVelocity({ vx: 2, vy: -1 }, 0)).toEqual({ vx: 2, vy: -1 });
  });

  it("reduces magnitude over time and more for longer dt", () => {
    const a = decayVelocity({ vx: 2, vy: 0 }, 16);
    const b = decayVelocity({ vx: 2, vy: 0 }, 100);
    expect(Math.abs(a.vx)).toBeLessThan(2);
    expect(Math.abs(b.vx)).toBeLessThan(Math.abs(a.vx));
    expect(Math.sign(a.vx)).toBe(1); // direction preserved
  });
});
