/**
 * Unit tests for locator helpers in mediaoverlay/syncNarration.ts.
 *
 * Covers:
 *   - textLocatorForItem
 *   - combinedLocatorForItem
 *   - textLocatorToAudioLocator
 *   - findItemByAudioTime
 */

import {
  Link,
  Links,
  Locator,
  LocatorLocations,
  LocatorText,
} from "@readium/shared";
import {
  SyncNarrationItem,
  combinedLocatorForItem,
  findItemByAudioTime,
  parseSyncNarration,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "../mediaoverlay/syncNarration";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

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

function makeNarrationPublication(
  readingOrder: Link[],
  responses: Record<string, unknown>,
  toc: Link[] = []
): {
  publication: ReadiumPublication;
  get: jest.Mock;
} {
  const get = jest.fn((link: Link) => ({
    readAsJSON: async () => responses[link.href],
  }));
  const publication = {
    baseURL: "https://example.test/book/",
    readingOrder: { items: readingOrder },
    manifest: { toc: new Links(toc) },
    get,
  } as unknown as ReadiumPublication;
  return { publication, get };
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

  describe("parseSyncNarration URI templates", () => {
    const narration = {
      narration: [{ audio: "chapter.mp3#t=0,3", text: "chapter.xhtml#p1" }],
    };

    it("expands an alternate template using the owning reading-order resource", async () => {
      const sidecar = new Link({
        href: "overlay.json{?ref}",
        templated: true,
        type: "application/vnd.readium.narration+json",
      });
      const chapter = new Link({
        href: "chapter.xhtml",
        alternates: new Links([sidecar]),
      });
      const { publication, get } = makeNarrationPublication(
        [chapter],
        { "overlay.json?ref=chapter.xhtml": narration }
      );

      const items = await parseSyncNarration(publication);

      expect(items).toHaveLength(1);
      expect(items[0].audioHref).toBe("chapter.mp3");
      expect(get).toHaveBeenCalledWith(
        expect.objectContaining({
          href: "overlay.json?ref=chapter.xhtml",
          templated: false,
        })
      );
    });

    it("skips unresolved optional templates while preserving plain sidecars", async () => {
      const unresolvedSidecar = new Link({
        href: "overlay.json{?missing}",
        templated: true,
        type: "application/vnd.readium.narration+json",
      });
      const plainSidecar = new Link({
        href: "plain-overlay.json",
        type: "application/vnd.readium.narration+json",
      });
      const unresolvedChapter = new Link({
        href: "missing.xhtml",
        alternates: new Links([unresolvedSidecar]),
      });
      const plainChapter = new Link({
        href: "plain.xhtml",
        alternates: new Links([plainSidecar]),
      });
      const { publication, get } = makeNarrationPublication(
        [unresolvedChapter, plainChapter],
        { "plain-overlay.json": narration }
      );

      const items = await parseSyncNarration(publication);

      expect(items).toHaveLength(1);
      expect(items[0].position).toBe(1);
      expect(get).toHaveBeenCalledTimes(1);
      expect(get).toHaveBeenCalledWith(
        expect.objectContaining({ href: "plain-overlay.json" })
      );
    });
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

  it("returns undefined for a no-textId locator when resource fallback is disallowed", () => {
    const loc = new Locator({ href: "chap1.html", type: "text/html", locations: new LocatorLocations({}) });
    expect(textLocatorToAudioLocator(items, loc, false)).toBeUndefined();
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

  it("returns undefined for an unmatched textId when resource fallback is disallowed", () => {
    // Same-resource ToC tap at a cue-less anchor must not rewind audio (issue #139).
    const loc = textLocator("chap1.html", "unknown");
    expect(textLocatorToAudioLocator(items, loc, false)).toBeUndefined();
  });

  it("still maps an exact href+id match when resource fallback is disallowed", () => {
    // Gating only suppresses the imprecise fallback; a real cue match always maps.
    const loc = textLocator("chap1.html", "p2");
    const audioLoc = textLocatorToAudioLocator(items, loc, false);
    expect(audioLoc).not.toBeUndefined();
    expect(audioLoc!.href).toBe("chap1.mp3");
    expect(audioLoc!.locations.fragments).toContain("t=5");
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
    // This retains Guided Navigation's legacy boundary behavior.
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


describe("Sync Narration scoped ToC ownership", () => {
  const cue = (id: string, start = 0, file = "chap.xhtml") => ({
    text: `${file}#${id}`, audio: `chap.mp3#t=${start},${start + 2}`,
  });
  const toc = [
    new Link({ href: "chap.xhtml#parent", title: "Parent", children: new Links([
      new Link({ href: "chap.xhtml#sub", title: "Sub" }),
    ]) }),
    new Link({ href: "other.xhtml", title: "Other" }),
  ];
  async function parse(narration: unknown[], links = toc) {
    const chapter = new Link({ href: "chap.xhtml", duration: 30, alternates: new Links([
      new Link({ href: "overlay.json", type: "application/vnd.readium.narration+json" }),
    ]) });
    const { publication } = makeNarrationPublication([chapter], { "overlay.json": { narration } }, links);
    return parseSyncNarration(publication);
  }
  it("assigns an audio-less parent and restores it after nested heading lists", async () => {
    const items = await parse([{ text: "chap.xhtml#parent", narration: [
      cue("p1"), { narration: [cue("sub", 2), cue("p2", 4)] }, cue("p3", 6),
    ] }]);
    expect(items.map(i => i.tocHref)).toEqual([
      "chap.xhtml#parent", "chap.xhtml#sub", "chap.xhtml#sub", "chap.xhtml#parent",
    ]);
    expect(items.map(i => i.tocTitle)).toEqual(["Parent", "Sub", "Sub", "Parent"]);
    expect(items.map(i => i.audioStart)).toEqual([0, 2, 4, 6]);
    expect(items.every(i => i.position === 0 && i.readingOrderDuration === 30)).toBe(true);
  });
  it("emits own audio before children without activating caller continuation", async () => {
    const items = await parse([{ text: "chap.xhtml#parent", narration: [
      { ...cue("sub", 2), narration: [cue("p2", 4)] }, cue("p3", 6),
    ] }]);
    expect(items.map(i => i.textId)).toEqual(["sub", "p2", "p3"]);
    expect(items.map(i => i.tocHref)).toEqual(["chap.xhtml#sub", "chap.xhtml#sub", "chap.xhtml#parent"]);
  });
  it("switches to file-only ownership and clears stale owners across resources", async () => {
    const items = await parse([cue("sub"), cue("p2", 2, "other.xhtml"),
      cue("p3", 4, "unknown.xhtml"), cue("p4", 6)]);
    expect(items.map(i => i.tocHref)).toEqual(["chap.xhtml#sub", "other.xhtml", undefined, undefined]);
    expect(items[1].tocTitle).toBe("Other");
  });
  it("continues a direct narrated subsection over an inherited parent", async () => {
    const items = await parse([{ text: "chap.xhtml#parent", narration: [cue("sub"), cue("p2", 2)] }]);
    expect(items.map(i => i.tocHref)).toEqual(["chap.xhtml#sub", "chap.xhtml#sub"]);
    expect(textLocatorToAudioLocator(items, textLocator("chap.xhtml", "parent"), false, true)).toBeUndefined();
  });
  it("does not activate audio-less flat headings", async () => {
    const items = await parse([{text: "chap.xhtml#sub"}, cue("p2", 2)]);
    expect(items[0].tocHref).toBeUndefined();
  });
  it("keeps flat narrated headings active and does not fabricate owners without ToC", async () => {
    expect((await parse([cue("sub"), cue("p2", 2)])).map(i => i.tocHref))
      .toEqual(["chap.xhtml#sub", "chap.xhtml#sub"]);
    expect((await parse([cue("sub")], []))[0].tocHref).toBeUndefined();
    expect(await parse([null, {}, { narration: [] }])).toEqual([]);
  });
});


describe("Sync Narration precise lookup policy", () => {
  const items = [
    makeItem({textHref: "other.xhtml", textId: "p1", tocHref: "other.xhtml#section", audioHref: "other.mp3", audioStart: 0, audioEnd: 5}),
    makeItem({textHref: "chap.xhtml", textId: "p1", tocHref: "chap.xhtml#section", audioHref: "chap.mp3", audioStart: 0, audioEnd: 5}),
    makeItem({textHref: "chap.xhtml", textId: "section", tocHref: "chap.xhtml#sub", audioHref: "chap.mp3", audioStart: 5, audioEnd: 8}),
    makeItem({textHref: "chap.xhtml", textId: "p3", tocHref: "chap.xhtml#parent", audioHref: "chap.mp3", audioStart: 10, audioEnd: 15}),
  ];
  const map = (locator: Locator, fallback = false) =>
    textLocatorToAudioLocator(items, locator, fallback, true);
  it("seeks assigned structural owners with fallback disabled and exact cues win", () => {
    expect(map(textLocator("chap.xhtml", "parent"))?.locations.fragments).toEqual(["t=10"]);
    expect(map(textLocator("chap.xhtml", "section"))?.locations.fragments).toEqual(["t=5"]);
    expect(map(textLocator("other.xhtml", "section"))?.href).toBe("other.mp3");
    expect(map(textLocator("chap.xhtml", "unknown"))).toBeUndefined();
    expect(textLocatorToAudioLocator(items, textLocator("chap.xhtml", "parent"), false)).toBeUndefined();
  });
  it.each(["chap.xhtml", "chap.mp3"])("selects explicit time in text or audio resource %s", href => {
    const loc = new Locator({href, type: "text/html", locations: new LocatorLocations({fragments: ["p1", "t=10"]})});
    expect(map(loc)?.locations.fragments).toEqual(["t=10"]);
    expect(map(new Locator({href, type: "text/html", locations: new LocatorLocations({fragments: ["t=9"]})}))?.locations.fragments).toEqual(["t=9"]);
    expect(map(new Locator({href, type: "text/html", locations: new LocatorLocations({fragments: ["t=5"]})}))?.locations.fragments).toEqual(["t=5"]);
    expect(map(new Locator({href, type: "text/html", locations: new LocatorLocations({fragments: ["p1", "t=20"]})}), true)).toBeUndefined();
  });
  it("time chooses a distinct audio resource at shared boundaries and gaps before an anchor", () => {
    const cues = [
      makeItem({textHref: "chap.xhtml", textId: "p1", audioHref: "first.mp3", audioStart: 0, audioEnd: 5}),
      makeItem({textHref: "chap.xhtml", textId: "p2", audioHref: "second.mp3", audioStart: 5, audioEnd: 8}),
      makeItem({textHref: "chap.xhtml", textId: "p3", audioHref: "third.mp3", audioStart: 10, audioEnd: 15}),
    ];
    for (const [time, href] of [[5, "second.mp3"], [9, "third.mp3"], [10, "third.mp3"]] as const) {
      const locator = new Locator({href: "chap.xhtml", type: "text/html", locations: new LocatorLocations({fragments: ["p1", `t=${time}`]})});
      const mapped = textLocatorToAudioLocator(cues, locator, false, true);
      expect(mapped?.href).toBe(href);
      expect(mapped?.locations.fragments).toEqual([`t=${time}`]);
    }
  });
  it("skips a zero-duration boundary cue when seeking to an upcoming cue", () => {
    const cues = [makeItem({textHref: "chap.xhtml", textId: "empty", audioHref: "empty.mp3", audioStart: 5, audioEnd: 5}),
      makeItem({textHref: "chap.xhtml", textId: "next", audioHref: "next.mp3", audioStart: 10, audioEnd: 15})];
    const mapped = textLocatorToAudioLocator(cues, textLocator("chap.xhtml", "t=5"), false, true);
    expect(mapped?.href).toBe("next.mp3");
    expect(mapped?.locations.fragments).toEqual(["t=5"]);
    expect(textLocatorToAudioLocator(cues.slice(0, 1), textLocator("chap.xhtml", "t=5"), false, true)).toBeUndefined();
  });
  it.each([null, 2])("treats missing or malformed end %s as open-ended", end => {
    const cues = [makeItem({textHref: "chap.xhtml", textId: "p1", audioHref: "open.mp3", audioStart: 5, audioEnd: end}),
      makeItem({textHref: "chap.xhtml", textId: "p2", audioHref: "next.mp3", audioStart: 10, audioEnd: 15})];
    const mapped = textLocatorToAudioLocator(cues, textLocator("chap.xhtml", "t=12"), false, true);
    expect(mapped?.href).toBe("open.mp3");
    expect(mapped?.locations.fragments).toEqual(["t=12"]);
  });
  it("ignores malformed time as an anchor while preserving fragmentless progression", () => {
    const loc = new Locator({href: "chap.xhtml", type: "text/html", locations: new LocatorLocations({fragments: ["t=oops", "parent"]})});
    expect(map(loc)?.locations.fragments).toEqual(["t=10"]);
    expect(map(textLocator("chap.xhtml", undefined, .5), true)?.locations.fragments).toEqual(["t=2.5"]);
    expect(map(textLocator("chap.xhtml"))).toBeUndefined();
  });
});


describe("ADR scoped heading and structural-resource regressions", () => {
  async function parse(json: unknown, toc: string[] = []) {
    const chapter = new Link({ href: "ch.xhtml", alternates: new Links([
      new Link({ href: "overlay.json", type: "application/vnd.readium.narration+json" }),
    ]) });
    const { publication } = makeNarrationPublication([chapter], { "overlay.json": json },
      toc.map(href => new Link({ href })));
    return parseSyncNarration(publication);
  }
  const cue = (text: string, audio: string) => ({ text, audio });
  const sectionCues = {
    narration: [
      { text: "one.xhtml#section", narration: [cue("one.xhtml#p1", "one.mp3#t=0,5")] },
      { text: "two.xhtml#section", narration: [cue("two.xhtml#p2", "two.mp3#t=7,12")] },
    ],
  };

  it("restores active heading A after matching container B", async () => {
    const items = await parse({ narration: [{ text: "ch.xhtml#parent", narration: [
      cue("ch.xhtml#A", "ch.mp3#t=0,5"),
      { text: "ch.xhtml#B", narration: [cue("ch.xhtml#inside", "ch.mp3#t=5,10")] },
      cue("ch.xhtml#after", "ch.mp3#t=10,15"),
    ] }] }, ["ch.xhtml#parent", "ch.xhtml#A", "ch.xhtml#B"]);
    expect(items.map(item => item.tocHref)).toEqual(["ch.xhtml#A", "ch.xhtml#B", "ch.xhtml#A"]);
  });

  it("restores active heading A after a generic wrapper containing B", async () => {
    const items = await parse({ narration: [{ text: "ch.xhtml#parent", narration: [
      cue("ch.xhtml#A", "ch.mp3#t=0,5"),
      { narration: [cue("ch.xhtml#B", "ch.mp3#t=5,10"), cue("ch.xhtml#inside", "ch.mp3#t=10,15")] },
      cue("ch.xhtml#after", "ch.mp3#t=15,20"),
    ] }] }, ["ch.xhtml#parent", "ch.xhtml#A", "ch.xhtml#B"]);
    expect(items.map(item => item.tocHref)).toEqual(["ch.xhtml#A", "ch.xhtml#B", "ch.xhtml#B", "ch.xhtml#A"]);
  });

  it("distinguishes duplicate audio-less structural IDs by resource", async () => {
    const items = await parse(sectionCues, ["one.xhtml#section", "two.xhtml#section"]);
    const mapped = textLocatorToAudioLocator(items, textLocator("two.xhtml", "section"), false, true);
    expect(mapped?.href).toBe("two.mp3");
    expect(mapped?.locations.fragments).toEqual(["t=7"]);
  });

  it("allows cross-resource unknown-anchor fallback under Sync policy", async () => {
    const items = await parse(sectionCues, ["one.xhtml#section", "two.xhtml#section"]);
    const mapped = textLocatorToAudioLocator(items, textLocator("two.xhtml", "unknown"), true, true);
    expect(mapped?.href).toBe("two.mp3");
    expect(mapped?.locations.fragments).toEqual(["t=7"]);
    expect(textLocatorToAudioLocator(items, textLocator("two.xhtml", "unknown"), false, true)).toBeUndefined();
  });

  const invalidSidecars: unknown[] = [null, undefined, [], 7, "invalid", {},
    { narration: null }, { narration: "invalid" }, { narration: [] }];
  it.each(invalidSidecars.map(json => [json]))(
    "does not invent cues for invalid or empty top-level sidecar %j", async json => {
      expect(await parse(json)).toEqual([]);
    }
  );
});


describe("Sync playback cue boundaries", () => {
  const ending = makeItem({textHref: "one.xhtml", textId: "boundary", tocHref: "one.xhtml#section",
    audioHref: "track.mp3", audioStart: 14, audioEnd: 16});
  const starting = makeItem({textHref: "two.xhtml", textId: "heading", tocHref: "two.xhtml#section",
    audioHref: "track.mp3", audioStart: 16, audioEnd: 18});
  const lookup = (items: SyncNarrationItem[], time: number) =>
    findItemByAudioTime(items, "track.mp3", time, true);
  it("Sync selects the starting cue at 16 while Guided default keeps the ending cue", () => {
    const unrelated = {...starting, audioHref: "other.mp3"};
    const items = [unrelated, ending, starting];
    expect(lookup(items, 16)).toBe(starting);
    expect(findItemByAudioTime(items, "track.mp3", 16)).toBe(ending);
    expect(lookup(items, 18)).toBeUndefined();
  });
  it.each([null, 2])("Sync retains open-ended matching for missing or malformed end %s", end => {
    const item = {...starting, audioStart: 5, audioEnd: end};
    expect(lookup([item], 99)).toBe(item);
  });
  it("Sync does not fabricate a start for an untimed cue", () => {
    const item = {...starting, audioStart: null, audioEnd: null};
    expect(lookup([item], 16)).toBeUndefined();
    expect(findItemByAudioTime([item], "track.mp3", 16)).toBe(item);
  });
});
