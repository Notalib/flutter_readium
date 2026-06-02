/**
 * Unit tests for pure helpers in Audio/audioNavigator.ts.
 *
 * Covers:
 *   - makeAudioTotalProgressionFn  (via __testing__ export)
 *   - buildStatePayload
 *
 * AudioNavigator itself is not instantiated — its constructor requires a DOM
 * audio context and live media elements that aren't available in the Node.js
 * test environment. We fake only the interfaces these functions read.
 */

import { Locator, LocatorLocations } from "@readium/shared";
import { buildStatePayload, __testing__ } from "../Audio/audioNavigator";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { AudioNavigator } from "@readium/navigator";

const { makeAudioTotalProgressionFn } = __testing__;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Builds a minimal fake ReadiumPublication whose readingOrder.items satisfies
 * what makeAudioTotalProgressionFn reads: items[].href and items[].duration.
 */
function fakePubWithTracks(
  tracks: Array<{ href: string; duration?: number }>
): ReadiumPublication {
  return {
    readingOrder: {
      items: tracks,
    },
  } as unknown as ReadiumPublication;
}

/**
 * Builds a Locator with a `t=<seconds>` time fragment so that
 * locator.locations.time() returns the given number.
 * (LocatorLocations.time() parses the first `t=<n>` from fragments — integer only.)
 */
function audioLocator(href: string, timeSecs: number): Locator {
  return new Locator({
    href,
    type: "audio/mpeg",
    locations: new LocatorLocations({
      fragments: [`t=${Math.round(timeSecs)}`],
    }),
  });
}

/**
 * Minimal AudioNavigator stub for buildStatePayload.
 */
function fakeNav(opts: {
  currentTime: number;
  duration: number;
  currentLocator?: Locator;
}): AudioNavigator {
  const loc = opts.currentLocator ?? new Locator({
    href: "chap1.mp3",
    type: "audio/mpeg",
    locations: new LocatorLocations({ fragments: [`t=${Math.round(opts.currentTime)}`] }),
  });
  return {
    currentTime: opts.currentTime,
    duration: opts.duration,
    currentLocator: loc,
  } as unknown as AudioNavigator;
}

// ---------------------------------------------------------------------------
// makeAudioTotalProgressionFn
// ---------------------------------------------------------------------------

describe("makeAudioTotalProgressionFn", () => {
  it("returns a no-op (undefined) function when any track has no duration", () => {
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3" },               // missing duration
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap1.mp3", 0);
    expect(fn(loc)).toBeUndefined();
  });

  it("returns a no-op (undefined) function when any track has duration <= 0", () => {
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 0 }, // zero duration is invalid
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap1.mp3", 0);
    expect(fn(loc)).toBeUndefined();
  });

  it("computes 0 at the very start of the first track (t=0)", () => {
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 10 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap1.mp3", 0);
    expect(fn(loc)).toBeCloseTo(0.0);
  });

  it("computes 0.5 at mid-point of a two-track equal-length publication", () => {
    // tracks: 10s + 10s = 20s total; chap1 at t=10 → (0+10)/20 = 0.5
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 10 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap1.mp3", 10);
    expect(fn(loc)).toBeCloseTo(0.5);
  });

  it("computes correct cumulative offset for the second track", () => {
    // tracks: 10s + 20s = 30s total; chap2 at t=0 → (10+0)/30 ≈ 0.333
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 20 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap2.mp3", 0);
    expect(fn(loc)).toBeCloseTo(10 / 30);
  });

  it("computes 1.0 at the very end of the last track", () => {
    // tracks: 10s + 20s = 30s total; chap2 at t=20 → (10+20)/30 = 1.0
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 20 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap2.mp3", 20);
    expect(fn(loc)).toBeCloseTo(1.0);
  });

  it("clamps values > 1 to 1.0", () => {
    // chap2 at t=999 would exceed total → clamped to 1.0
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
      { href: "chap2.mp3", duration: 10 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("chap2.mp3", 999);
    expect(fn(loc)).toBe(1.0);
  });

  it("returns undefined when the locator's href is not in the reading order", () => {
    const pub = fakePubWithTracks([
      { href: "chap1.mp3", duration: 10 },
    ]);
    const fn = makeAudioTotalProgressionFn(pub);
    const loc = audioLocator("unknown.mp3", 5);
    expect(fn(loc)).toBeUndefined();
  });

  it("handles a single-track publication correctly", () => {
    const pub = fakePubWithTracks([{ href: "audio.mp3", duration: 100 }]);
    const fn = makeAudioTotalProgressionFn(pub);
    expect(fn(audioLocator("audio.mp3", 0))).toBeCloseTo(0.0);
    expect(fn(audioLocator("audio.mp3", 50))).toBeCloseTo(0.5);
    expect(fn(audioLocator("audio.mp3", 100))).toBeCloseTo(1.0);
  });

  it("strips a #fragment from the locator href before matching", () => {
    const pub = fakePubWithTracks([{ href: "chap1.mp3", duration: 10 }]);
    const fn = makeAudioTotalProgressionFn(pub);
    // Construct a locator with a fragment in the href itself (unusual but
    // the code explicitly splits on '#').
    const loc = new Locator({
      href: "chap1.mp3#extra",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=5"] }),
    });
    expect(fn(loc)).toBeCloseTo(0.5);
  });
});

// ---------------------------------------------------------------------------
// buildStatePayload
// ---------------------------------------------------------------------------

describe("buildStatePayload", () => {
  it("returns a JSON string with the expected top-level keys and correct values", () => {
    const nav = fakeNav({ currentTime: 2.5, duration: 10.0 });
    const payload = JSON.parse(buildStatePayload("playing", nav));
    expect(payload.state).toBe("playing");
    expect(payload.currentOffset).toBe(2500);
    expect(payload.currentDuration).toBe(10000);
    expect(payload.currentLocator.href).toBe("chap1.mp3");
  });

  it("sets the state field correctly", () => {
    const nav = fakeNav({ currentTime: 0, duration: 10 });
    expect(JSON.parse(buildStatePayload("paused", nav)).state).toBe("paused");
    expect(JSON.parse(buildStatePayload("playing", nav)).state).toBe("playing");
  });

  it("rounds currentTime to milliseconds (ms = seconds * 1000)", () => {
    const nav = fakeNav({ currentTime: 2.5, duration: 10 });
    expect(JSON.parse(buildStatePayload("playing", nav)).currentOffset).toBe(2500);
  });

  it("rounds currentDuration to milliseconds", () => {
    const nav = fakeNav({ currentTime: 0, duration: 10.5 });
    expect(JSON.parse(buildStatePayload("playing", nav)).currentDuration).toBe(10500);
  });

  it("sets currentDuration to null when nav.duration is 0", () => {
    const nav = fakeNav({ currentTime: 0, duration: 0 });
    expect(JSON.parse(buildStatePayload("playing", nav)).currentDuration).toBeNull();
  });

  it("sets currentDuration to null when nav.duration is negative", () => {
    const nav = fakeNav({ currentTime: 0, duration: -1 });
    expect(JSON.parse(buildStatePayload("paused", nav)).currentDuration).toBeNull();
  });

  it("uses the provided locator instead of nav.currentLocator when supplied", () => {
    const navLoc = new Locator({
      href: "chap1.mp3", type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=0"] }),
    });
    const overrideLoc = new Locator({
      href: "chap2.mp3", type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=5"] }),
    });
    const nav = fakeNav({ currentTime: 0, duration: 20, currentLocator: navLoc });
    const payload = JSON.parse(buildStatePayload("playing", nav, overrideLoc));
    expect(payload.currentLocator.href).toBe("chap2.mp3");
  });

  it("uses nav.currentLocator when no locator argument is given", () => {
    const navLoc = new Locator({
      href: "chap1.mp3", type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=3"] }),
    });
    const nav = fakeNav({ currentTime: 3, duration: 20, currentLocator: navLoc });
    const payload = JSON.parse(buildStatePayload("playing", nav));
    expect(payload.currentLocator.href).toBe("chap1.mp3");
  });

  it("serializes the locator so fragments are preserved in the JSON", () => {
    const loc = new Locator({
      href: "chap1.mp3", type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=7"] }),
    });
    const nav = fakeNav({ currentTime: 7, duration: 20, currentLocator: loc });
    const payload = JSON.parse(buildStatePayload("playing", nav));
    expect(payload.currentLocator.locations.fragments).toContain("t=7");
  });

  it("rounds fractional milliseconds (Math.round)", () => {
    // 2.5004 seconds × 1000 = 2500.4 → rounds to 2500
    const nav = fakeNav({ currentTime: 2.5004, duration: 10.9994 });
    const p = JSON.parse(buildStatePayload("playing", nav));
    expect(p.currentOffset).toBe(2500);
    expect(p.currentDuration).toBe(10999);
  });
});
