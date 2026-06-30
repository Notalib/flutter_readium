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
import {
  buildStatePayload,
  seekAudioAndResume,
  SeekableAudioNavigator,
  __testing__,
} from "../navigators/FlutterAudioNavigator";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { AudioNavigator } from "@readium/navigator";

const { makeAudioTotalProgressionFn, withTocHref } = __testing__;

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
    expect(payload.totalProgressDuration).toBeNull();
    expect(payload.totalDuration).toBeNull();
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

  it("includes totalProgressDuration when provided", () => {
    const nav = fakeNav({ currentTime: 3, duration: 20 });
    const payload = JSON.parse(buildStatePayload("playing", nav, undefined, 1234));
    expect(payload.totalProgressDuration).toBe(1234);
  });

  it("emits totalProgressDuration as null when omitted", () => {
    const nav = fakeNav({ currentTime: 3, duration: 20 });
    const payload = JSON.parse(
      buildStatePayload("playing", nav, undefined, undefined),
    );
    expect(payload.totalProgressDuration).toBeNull();
  });

  it("includes totalDuration when provided", () => {
    const nav = fakeNav({ currentTime: 3, duration: 20 });
    const payload = JSON.parse(buildStatePayload("playing", nav, undefined, undefined, 60000));
    expect(payload.totalDuration).toBe(60000);
  });

  it("emits totalDuration as null when omitted", () => {
    const nav = fakeNav({ currentTime: 3, duration: 20 });
    const payload = JSON.parse(buildStatePayload("playing", nav));
    expect(payload.totalDuration).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// withTocHref
// ---------------------------------------------------------------------------

describe("withTocHref", () => {
  function makeLocator(href: string, otherLocations?: Map<string, any>): Locator {
    return new Locator({
      href,
      type: "audio/mpeg",
      locations: new LocatorLocations({
        fragments: ["t=0"],
        progression: 0.25,
        totalProgression: 0.1,
        otherLocations,
      }),
    });
  }

  it("returns the locator unchanged when tocHref is undefined", () => {
    const loc = makeLocator("chap1.mp3");
    const result = withTocHref(loc, undefined);
    expect(result).toBe(loc);
  });

  it("injects tocHref into otherLocations when not already present", () => {
    const loc = makeLocator("chap1.mp3");
    const result = withTocHref(loc, "chap1.xhtml#intro");
    expect(result.locations.otherLocations?.get("tocHref")).toBe("chap1.xhtml#intro");
  });

  it("preserves existing otherLocations entries alongside the new tocHref", () => {
    const existing = new Map<string, any>([["cssSelector", "#par1"]]);
    const loc = makeLocator("chap1.mp3", existing);
    const result = withTocHref(loc, "chap1.xhtml");
    expect(result.locations.otherLocations?.get("cssSelector")).toBe("#par1");
    expect(result.locations.otherLocations?.get("tocHref")).toBe("chap1.xhtml");
  });

  it("preserves href, type, progression, totalProgression, and fragments", () => {
    const loc = makeLocator("chap1.mp3");
    const result = withTocHref(loc, "chap1.xhtml");
    expect(result.href).toBe("chap1.mp3");
    expect(result.type).toBe("audio/mpeg");
    expect(result.locations.progression).toBe(0.25);
    expect(result.locations.totalProgression).toBe(0.1);
    expect(result.locations.fragments).toContain("t=0");
  });

  it("does not mutate the original locator's otherLocations", () => {
    const original = new Map<string, any>([["cssSelector", "#par1"]]);
    const loc = makeLocator("chap1.mp3", original);
    withTocHref(loc, "chap1.xhtml");
    expect(original.has("tocHref")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// seekAudioAndResume
// ---------------------------------------------------------------------------

/**
 * Records the order of pause/play/go calls so tests can assert that the
 * pause-before-seek / resume-after-seek sequencing (the regression fix) holds.
 *
 * `goResolves` controls whether the simulated `go()` reports success; the
 * resume `play()` fires from inside the go callback regardless, mirroring the
 * real navigator which always invokes the completion callback.
 */
function recordingNav(opts: {
  isPlaying: boolean;
  goResolves?: boolean;
  currentHref?: string;
  currentTime?: number;
}): SeekableAudioNavigator & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    get isPlaying() {
      return opts.isPlaying;
    },
    get currentLocator() {
      return new Locator({
        href: opts.currentHref ?? "other.mp3",
        type: "audio/mpeg",
        locations: new LocatorLocations({
          fragments: [`t=${opts.currentTime ?? 0}`],
        }),
      });
    },
    get currentTime() {
      return opts.currentTime ?? 0;
    },
    pause() {
      calls.push("pause");
    },
    play() {
      calls.push("play");
    },
    go(_locator: Locator, _animated: boolean, cb: (ok: boolean) => void): Promise<void> {
      calls.push("go");
      cb(opts.goResolves ?? true);
      return Promise.resolve();
    },
  };
}

describe("seekAudioAndResume", () => {
  const loc = () =>
    new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=5"] }),
    });

  it("pauses before seeking when currently playing, then resumes after", async () => {
    const nav = recordingNav({ isPlaying: true });
    await seekAudioAndResume(nav, loc(), true);
    // pause must precede go (forces upstream poll restart), play must follow go.
    expect(nav.calls).toEqual(["pause", "go", "play"]);
  });

  it("does not pause when already paused, but still resumes after seeking", async () => {
    const nav = recordingNav({ isPlaying: false });
    await seekAudioAndResume(nav, loc(), true);
    expect(nav.calls).toEqual(["go", "play"]);
  });

  it("does not resume when resumePlaying is false (was playing)", async () => {
    const nav = recordingNav({ isPlaying: true });
    await seekAudioAndResume(nav, loc(), false);
    // Still pauses (to keep the engine state consistent) but never re-plays.
    expect(nav.calls).toEqual(["pause", "go"]);
  });

  it("does not resume when resumePlaying is false (was paused)", async () => {
    const nav = recordingNav({ isPlaying: false });
    await seekAudioAndResume(nav, loc(), false);
    expect(nav.calls).toEqual(["go"]);
  });

  it("does not resume playback when the seek fails", async () => {
    const nav = recordingNav({ isPlaying: true, goResolves: false });
    await seekAudioAndResume(nav, loc(), true);
    // Failed seek: pause + go ran, but no resume since go reported failure.
    expect(nav.calls).toEqual(["pause", "go"]);
  });

  it("skips go() and restarts playback when already at the target position", async () => {
    // Same href + same time as loc() (t=5): a real seek would hang upstream go(),
    // so the helper must restart playback directly instead of seeking.
    const nav = recordingNav({ isPlaying: true, currentHref: "chap1.mp3", currentTime: 5 });
    await seekAudioAndResume(nav, loc(), true);
    expect(nav.calls).toEqual(["pause", "play"]);
  });

  it("skips go() and plays once when already at target and currently paused", async () => {
    const nav = recordingNav({ isPlaying: false, currentHref: "chap1.mp3", currentTime: 5 });
    await seekAudioAndResume(nav, loc(), true);
    expect(nav.calls).toEqual(["play"]);
  });

  it("does nothing when already at target and not resuming", async () => {
    const nav = recordingNav({ isPlaying: false, currentHref: "chap1.mp3", currentTime: 5 });
    await seekAudioAndResume(nav, loc(), false);
    expect(nav.calls).toEqual([]);
  });

  it("still seeks when the target time differs beyond the epsilon", async () => {
    const nav = recordingNav({ isPlaying: true, currentHref: "chap1.mp3", currentTime: 4 });
    await seekAudioAndResume(nav, loc(), true);
    expect(nav.calls).toEqual(["pause", "go", "play"]);
  });
});
