/**
 * Unit tests for Epub/epubNavigator.ts → enrichWithTotalProgression.
 *
 * Formula: (position - 1 + progression) / totalPositions, clamped to [0, 1].
 * Falls back gracefully when position or progression are absent.
 */

import { Locator, LocatorLocations } from "@readium/shared";
import { enrichWithTotalProgression } from "../Epub/epubNavigator";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeLocator(opts: {
  href?: string;
  position?: number;
  progression?: number;
}): Locator {
  return new Locator({
    href: opts.href ?? "chap1.xhtml",
    type: "text/html",
    locations: new LocatorLocations({
      position: opts.position,
      progression: opts.progression,
    }),
  });
}

// ---------------------------------------------------------------------------
// Guard cases — locator returned unchanged
// ---------------------------------------------------------------------------

describe("enrichWithTotalProgression — guard cases", () => {
  it("returns locator unchanged when totalPositions is 0", () => {
    const loc = makeLocator({ position: 1, progression: 0 });
    const result = enrichWithTotalProgression(loc, 0);
    expect(result).toBe(loc);
  });

  it("returns locator unchanged when totalPositions is negative", () => {
    const loc = makeLocator({ position: 1, progression: 0 });
    const result = enrichWithTotalProgression(loc, -5);
    expect(result).toBe(loc);
  });

  it("returns locator unchanged when position is undefined", () => {
    const loc = makeLocator({ progression: 0.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result).toBe(loc);
  });

  it("returns locator unchanged when position is 0", () => {
    const loc = makeLocator({ position: 0, progression: 0.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result).toBe(loc);
  });

  it("returns locator unchanged when position is negative", () => {
    const loc = makeLocator({ position: -1, progression: 0.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result).toBe(loc);
  });
});

// ---------------------------------------------------------------------------
// Normal computation
// ---------------------------------------------------------------------------

describe("enrichWithTotalProgression — normal computation", () => {
  it("computes totalProgression for position=1, progression=0 (start of publication)", () => {
    // (1 - 1 + 0) / 10 = 0
    const loc = makeLocator({ position: 1, progression: 0 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBeCloseTo(0.0);
  });

  it("computes totalProgression for position=1, progression=0.5 (mid first page)", () => {
    // (1 - 1 + 0.5) / 10 = 0.05
    const loc = makeLocator({ position: 1, progression: 0.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBeCloseTo(0.05);
  });

  it("computes totalProgression for position=5, progression=0 (mid publication, paginated)", () => {
    // (5 - 1 + 0) / 10 = 0.4
    const loc = makeLocator({ position: 5, progression: 0 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBeCloseTo(0.4);
  });

  it("computes totalProgression for last position with full progression (end of publication)", () => {
    // (10 - 1 + 1.0) / 10 = 1.0
    const loc = makeLocator({ position: 10, progression: 1.0 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBeCloseTo(1.0);
  });

  it("falls back to progression=0 when progression is undefined", () => {
    // (3 - 1 + 0) / 10 = 0.2
    const loc = makeLocator({ position: 3 }); // progression undefined
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBeCloseTo(0.2);
  });

  it("clamps raw value > 1 to 1.0", () => {
    // (10 - 1 + 1.5) / 10 = 1.05 → clamped to 1.0
    const loc = makeLocator({ position: 10, progression: 1.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBe(1.0);
  });

  it("clamps raw value < 0 to 0.0", () => {
    // Negative progression (out-of-range but defensively handled):
    // raw = (1 - 1 + (-0.5)) / 10 = -0.05 → clamped to 0.0
    const loc = makeLocator({ position: 1, progression: -0.5 });
    const result = enrichWithTotalProgression(loc, 10);
    expect(result.locations.totalProgression).toBe(0.0);
  });

  it("preserves all other location fields on the returned locator", () => {
    const locator = new Locator({
      href: "chap5.xhtml",
      type: "text/html",
      title: "Chapter 5",
      locations: new LocatorLocations({
        position: 5,
        progression: 0.25,
        fragments: ["sec2"],
        otherLocations: new Map([["tocHref", "chap5.xhtml"]]),
      }),
    });
    const result = enrichWithTotalProgression(locator, 10);
    expect(result.href).toBe("chap5.xhtml");
    expect(result.title).toBe("Chapter 5");
    expect(result.locations.position).toBe(5);
    expect(result.locations.progression).toBe(0.25);
    expect(result.locations.fragments).toContain("sec2");
    expect(result.locations.otherLocations?.get("tocHref")).toBe("chap5.xhtml");
  });

  it("single-position publication returns 0 for first position", () => {
    // (1 - 1 + 0) / 1 = 0
    const loc = makeLocator({ position: 1, progression: 0 });
    const result = enrichWithTotalProgression(loc, 1);
    expect(result.locations.totalProgression).toBeCloseTo(0.0);
  });
});
