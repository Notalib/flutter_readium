/**
 * Unit tests for locator helpers in mediaoverlay/syncNarration.ts.
 *
 * Covers:
 *   - textLocatorForItem
 *   - combinedLocatorForItem
 *   - textLocatorToAudioLocator
 *   - findItemByAudioTime
 */

import { Link, Locator, LocatorLocations, LocatorText } from "@readium/shared";
import {
  SyncNarrationItem,
  combinedLocatorForItem,
  findItemByAudioTime,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "../mediaoverlay/syncNarration";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeItem(
  overrides: Partial<SyncNarrationItem> & {
    textHref: string;
    textId: string;
    audioHref: string;
    audioStart: number | null;
    audioEnd: number | null;
  }
): SyncNarrationItem {
  return {
    audio: `${overrides.audioHref}#t=${overrides.audioStart},${overrides.audioEnd}`,
    text: overrides.textId
      ? `${overrides.textHref}#${overrides.textId}`
      : overrides.textHref,
    position: overrides.position ?? 1,
    tocTitle: overrides.tocTitle,
    tocHref: overrides.tocHref,
    readingOrderDuration: overrides.readingOrderDuration,
    ...overrides,
  };
}

function textLocator(href: string, id?: string, progression?: number): Locator {
  const fragments = id ? [id] : [];
  const otherLocations = id
    ? new Map<string, any>([["cssSelector", `#${id}`]])
    : undefined;
  return new Locator({
    href,
    type: "text/html",
    locations: new LocatorLocations({ fragments, progression, otherLocations }),
  });
}

// ---------------------------------------------------------------------------
// textLocatorForItem
// ---------------------------------------------------------------------------

describe("textLocatorForItem", () => {
  it("builds a locator with the item's textHref", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3 });
    const loc = textLocatorForItem(item);
    expect(loc.href).toBe("chap1.html");
    expect(loc.type).toBe("text/html");
  });

  it("includes the textId as a fragment when present", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "par001", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3 });
    const loc = textLocatorForItem(item);
    expect(loc.locations.fragments).toContain("par001");
    expect(loc.locations.otherLocations?.get("cssSelector")).toBe("#par001");
  });

  it("produces empty fragments and no otherLocations when textId is empty and no tocHref", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3 });
    const loc = textLocatorForItem(item);
    expect(loc.locations.fragments).toHaveLength(0);
    expect(loc.locations.otherLocations).toBeUndefined();
  });

  it("attaches tocTitle as locator title when present on item", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "p1",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3,
      tocTitle: "Chapter 1",
    });
    const loc = textLocatorForItem(item);
    expect(loc.title).toBe("Chapter 1");
  });

  it("produces undefined title when item has no tocTitle", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3 });
    const loc = textLocatorForItem(item);
    expect(loc.title).toBeUndefined();
  });

  it("includes tocHref in otherLocations when set on item", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "p1",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3,
      tocHref: "chap1.html#sec1",
    });
    const loc = textLocatorForItem(item);
    expect(loc.locations.otherLocations?.get("tocHref")).toBe("chap1.html#sec1");
  });

  it("includes both cssSelector and tocHref when both textId and tocHref are set", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "par002",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3,
      tocHref: "chap1.html",
    });
    const loc = textLocatorForItem(item);
    expect(loc.locations.otherLocations?.get("cssSelector")).toBe("#par002");
    expect(loc.locations.otherLocations?.get("tocHref")).toBe("chap1.html");
  });

  it("sets otherLocations with only tocHref when textId is empty but tocHref is set", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3,
      tocHref: "chap1.html",
    });
    const loc = textLocatorForItem(item);
    expect(loc.locations.otherLocations?.get("tocHref")).toBe("chap1.html");
    expect(loc.locations.otherLocations?.has("cssSelector")).toBe(false);
  });

  it("does not include tocHref in otherLocations when item has no tocHref", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 3 });
    const loc = textLocatorForItem(item);
    expect(loc.locations.otherLocations?.has("tocHref")).toBeFalsy();
  });
});

// ---------------------------------------------------------------------------
// combinedLocatorForItem
// ---------------------------------------------------------------------------

describe("combinedLocatorForItem", () => {
  it("builds a locator with textHref as href", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5 });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=2.5"], progression: 0.5, totalProgression: 0.25 }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.href).toBe("chap1.html");
    expect(combined.type).toBe("text/html");
  });

  it("copies progression and totalProgression from the audio locator", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5 });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=2.5"], progression: 0.5, totalProgression: 0.25 }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.locations.progression).toBe(0.5);
    expect(combined.locations.totalProgression).toBe(0.25);
  });

  it("preserves the text item's fragment (textId) in the combined locator", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "par001", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5 });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=1.0"] }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.locations.fragments).toContain("par001");
    expect(combined.locations.otherLocations?.get("cssSelector")).toBe("#par001");
  });

  it("carries text field from the text locator (item.highlight)", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5,
      highlight: "Once upon a time",
    });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      text: new LocatorText({ highlight: "should be ignored" }),
      locations: new LocatorLocations({ fragments: ["t=1.0"] }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.text?.highlight).toBe("Once upon a time");
  });

  it("propagates tocHref from item into otherLocations", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "p1",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5,
      tocHref: "chap1.html#intro",
    });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=1.0"] }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.locations.otherLocations?.get("tocHref")).toBe("chap1.html#intro");
  });

  it("propagates both cssSelector and tocHref when both are on the item", () => {
    const item = makeItem({
      textHref: "chap1.html", textId: "par005",
      audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5,
      tocHref: "chap1.html",
    });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=1.0"] }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.locations.otherLocations?.get("cssSelector")).toBe("#par005");
    expect(combined.locations.otherLocations?.get("tocHref")).toBe("chap1.html");
  });

  it("does not include tocHref in otherLocations when item has no tocHref", () => {
    const item = makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5 });
    const audioLoc = new Locator({
      href: "chap1.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({ fragments: ["t=1.0"] }),
    });
    const combined = combinedLocatorForItem(item, audioLoc);
    expect(combined.locations.otherLocations?.has("tocHref")).toBeFalsy();
  });
});

// ---------------------------------------------------------------------------
// textLocatorToAudioLocator
// ---------------------------------------------------------------------------

describe("textLocatorToAudioLocator", () => {
  const items: SyncNarrationItem[] = [
    makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5, position: 1 }),
    makeItem({ textHref: "chap1.html", textId: "p2", audioHref: "chap1.mp3", audioStart: 5, audioEnd: 10, position: 1 }),
    makeItem({ textHref: "chap2.html", textId: "q1", audioHref: "chap2.mp3", audioStart: 0, audioEnd: 8, position: 2 }),
  ];

  it("returns undefined when no item matches the href", () => {
    const loc = textLocator("chap3.html", "x1");
    expect(textLocatorToAudioLocator(items, loc)).toBeUndefined();
  });

  it("maps exact href+id match to the audio locator at audioStart", () => {
    const loc = textLocator("chap1.html", "p2");
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc).not.toBeUndefined();
    expect(audioLoc!.href).toBe("chap1.mp3");
    expect(audioLoc!.locations.fragments).toContain("t=5");
  });

  it("maps to the first item in the href when no textId is given", () => {
    const loc = new Locator({ href: "chap1.html", type: "text/html", locations: new LocatorLocations({}) });
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc).not.toBeUndefined();
    expect(audioLoc!.href).toBe("chap1.mp3");
    expect(audioLoc!.locations.fragments).toContain("t=0");
  });

  it("falls back to first item in href when textId has no match", () => {
    // "chap1.html#unknown" — no SyncNarrationItem with textId="unknown"
    const loc = textLocator("chap1.html", "unknown");
    const audioLoc = textLocatorToAudioLocator(items, loc);
    // Fallback: first item for chap1.html
    expect(audioLoc).not.toBeUndefined();
    expect(audioLoc!.href).toBe("chap1.mp3");
    expect(audioLoc!.locations.fragments).toContain("t=0");
  });

  it("uses progression within the item range when audioStart/End are set", () => {
    // item p2: audioStart=5, audioEnd=10; progression=0.5 → timeOffset = 5 + 0.5*(10-5) = 7.5
    const loc = new Locator({
      href: "chap1.html",
      type: "text/html",
      locations: new LocatorLocations({ fragments: ["p2"], progression: 0.5, otherLocations: new Map([["cssSelector", "#p2"]]) }),
    });
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc!.locations.fragments).toContain("t=7.5");
  });

  it("prefers a t= fragment on the incoming locator over progression", () => {
    // When fragments = ["p2", "t=3.0"]:
    //   - targetId = "p2" (first fragment, no t= prefix)
    //   - matches item p2 (audioStart=5, audioEnd=10)
    //   - tFragment found: "t=3.0" → timeOffset = 3.0
    // The t= fragment wins over progression-based interpolation.
    const loc = new Locator({
      href: "chap1.html",
      type: "text/html",
      locations: new LocatorLocations({ fragments: ["p2", "t=3.0"], progression: 0.5 }),
    });
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc!.locations.fragments).toContain("t=3");
  });

  it("returns undefined when the matched item has null audioStart", () => {
    const noStartItems: SyncNarrationItem[] = [
      makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: null, audioEnd: null }),
    ];
    const loc = textLocator("chap1.html", "p1");
    expect(textLocatorToAudioLocator(noStartItems, loc)).toBeUndefined();
  });

  it("resolves the audio href from the matched item", () => {
    const loc = textLocator("chap2.html", "q1");
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc!.href).toBe("chap2.mp3");
    expect(audioLoc!.type).toBe("audio/mpeg");
  });

  it("strips a leading slash from href for normalised comparison", () => {
    // normalizeHref strips the leading slash, so "/chap1.html" matches "chap1.html"
    const loc = textLocator("/chap1.html", "p1");
    const audioLoc = textLocatorToAudioLocator(items, loc);
    expect(audioLoc).not.toBeUndefined();
    expect(audioLoc!.href).toBe("chap1.mp3");
  });
});

// ---------------------------------------------------------------------------
// findItemByAudioTime
// ---------------------------------------------------------------------------

describe("findItemByAudioTime", () => {
  const items: SyncNarrationItem[] = [
    makeItem({ textHref: "chap1.html", textId: "p1", audioHref: "chap1.mp3", audioStart: 0, audioEnd: 5 }),
    makeItem({ textHref: "chap1.html", textId: "p2", audioHref: "chap1.mp3", audioStart: 5, audioEnd: 10 }),
    makeItem({ textHref: "chap1.html", textId: "p3", audioHref: "chap1.mp3", audioStart: 10, audioEnd: null }),
    makeItem({ textHref: "chap2.html", textId: "q1", audioHref: "chap2.mp3", audioStart: 0, audioEnd: 8 }),
  ];

  it("finds the item whose range covers the current time", () => {
    const item = findItemByAudioTime(items, "chap1.mp3", 3.0);
    expect(item).not.toBeUndefined();
    expect(item!.textId).toBe("p1");
  });

  it("finds the first item at an exact shared boundary — p1.audioEnd === p2.audioStart", () => {
    // At time=5.0: p1 has audioEnd=5, so `timeSecs <= 5` is true — p1 wins (first match wins).
    // NOTE: this means exact cue-boundary time returns the ending cue, not the starting one.
    // This mirrors the upstream itemInRangeOfTime behaviour — the boundary belongs to
    // the cue that ends there, not the cue that starts there.
    const item = findItemByAudioTime(items, "chap1.mp3", 5.0);
    expect(item!.textId).toBe("p1");
  });

  it("finds item at exact upper boundary (inclusive)", () => {
    const item = findItemByAudioTime(items, "chap1.mp3", 10.0);
    // time=10 equals audioEnd of p2 → p2 wins; also matches p3 (open-ended).
    // The function iterates in order, so p2's end is checked first: timeSecs <= 10 → true.
    expect(item!.textId).toBe("p2");
  });

  it("handles open-ended cue (audioEnd === null) — matches any time >= audioStart", () => {
    const item = findItemByAudioTime(items, "chap1.mp3", 999.0);
    expect(item).not.toBeUndefined();
    expect(item!.textId).toBe("p3");
  });

  it("returns undefined when no item matches the href", () => {
    expect(findItemByAudioTime(items, "chap3.mp3", 2.0)).toBeUndefined();
  });

  it("returns undefined when time is before all items on a matched href", () => {
    // chap2.mp3 items start at 0; any negative time is before all
    expect(findItemByAudioTime(items, "chap2.mp3", -1)).toBeUndefined();
  });

  it("normalises hrefs for comparison (leading slash stripped)", () => {
    const item = findItemByAudioTime(items, "/chap1.mp3", 3.0);
    expect(item).not.toBeUndefined();
    expect(item!.textId).toBe("p1");
  });

  it("returns undefined for an empty items list", () => {
    expect(findItemByAudioTime([], "chap1.mp3", 3.0)).toBeUndefined();
  });

  it("matches on the correct file when multiple hrefs are present", () => {
    const item = findItemByAudioTime(items, "chap2.mp3", 4.0);
    expect(item!.textId).toBe("q1");
    expect(item!.audioHref).toBe("chap2.mp3");
  });
});
