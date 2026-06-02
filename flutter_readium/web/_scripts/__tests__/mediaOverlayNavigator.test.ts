/**
 * Unit tests for private helpers in Audio/mediaOverlayNavigator.ts.
 *
 * All functions are exposed via the module's __testing__ export.
 *
 * Covers:
 *   - _audioMimeType  (pure href → MIME type mapping)
 *   - _resolveItemHrefs  (relative → absolute href resolution)
 *   - _buildAudioReadingOrder  (synthetic reading order construction)
 */

import { Link } from "@readium/shared";
import { __testing__ } from "../Audio/mediaOverlayNavigator";
import { SyncNarrationItem } from "../Audio/syncNarration";
import { ReadiumPublication } from "../extensions/ReadiumPublication";

const { audioMimeType, resolveItemHrefs, buildAudioReadingOrder } = __testing__;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeItem(
  audioHref: string,
  audioStart: number | null,
  audioEnd: number | null,
  opts: Partial<SyncNarrationItem> = {}
): SyncNarrationItem {
  return {
    audio: audioHref,
    text: "chap.html",
    position: opts.position ?? 1,
    audioHref,
    audioStart,
    audioEnd,
    textHref: "chap.html",
    textId: "",
    readingOrderDuration: opts.readingOrderDuration,
    tocTitle: opts.tocTitle,
    ...opts,
  };
}

/**
 * Minimal fake publication that provides what _buildAudioReadingOrder reads:
 *   publication.manifest.linksWithRel("self")[0]?.href
 */
function fakePub(selfHref: string): ReadiumPublication {
  return {
    manifest: {
      linksWithRel: (rel: string) => rel === "self" ? [{ href: selfHref }] : [],
    },
  } as unknown as ReadiumPublication;
}

// ---------------------------------------------------------------------------
// _audioMimeType
// ---------------------------------------------------------------------------

describe("audioMimeType", () => {
  it("returns audio/mpeg for .mp3", () => {
    expect(audioMimeType("chapter1.mp3")).toBe("audio/mpeg");
  });

  it("returns audio/ogg for .ogg", () => {
    expect(audioMimeType("chapter1.ogg")).toBe("audio/ogg");
  });

  it("returns audio/ogg for .oga", () => {
    expect(audioMimeType("chapter1.oga")).toBe("audio/ogg");
  });

  it("returns audio/ogg; codecs=opus for .opus", () => {
    expect(audioMimeType("chapter1.opus")).toBe("audio/ogg; codecs=opus");
  });

  it("returns audio/mp4 for .m4a", () => {
    expect(audioMimeType("chapter1.m4a")).toBe("audio/mp4");
  });

  it("returns audio/mp4 for .aac", () => {
    expect(audioMimeType("chapter1.aac")).toBe("audio/mp4");
  });

  it("returns audio/wav for .wav", () => {
    expect(audioMimeType("chapter1.wav")).toBe("audio/wav");
  });

  it("returns audio/mpeg (default) for an unknown extension", () => {
    expect(audioMimeType("chapter1.flac")).toBe("audio/mpeg");
  });

  it("returns audio/mpeg (default) for a bare file name with no extension", () => {
    expect(audioMimeType("chapter1")).toBe("audio/mpeg");
  });

  it("handles an absolute URL with .mp3 correctly", () => {
    expect(audioMimeType("https://host/book/chapter1.mp3")).toBe("audio/mpeg");
  });
});

// ---------------------------------------------------------------------------
// _resolveItemHrefs
// ---------------------------------------------------------------------------

describe("resolveItemHrefs", () => {
  it("resolves an exact href match (absolute URL that cannot be caught by suffix matching)", () => {
    // Both item and reading-order entry already use the full absolute URL.
    // This exercises the `l.href === item.audioHref` branch — suffix matching
    // (`endsWith("/" + audioHref)`) would not fire here since the item href
    // itself is absolute and neither string is a suffix of the other.
    const abs = "https://host/book/chap1.mp3";
    const items = [makeItem(abs, 0, 5)];
    const readingOrder = [new Link({ href: abs, type: "audio/mpeg" })];
    const resolved = resolveItemHrefs(items, readingOrder);
    expect(resolved[0].audioHref).toBe(abs);
  });

  it("resolves a relative href via suffix match (relative → absolute)", () => {
    const items = [makeItem("chap1.mp3", 0, 5)];
    const readingOrder = [new Link({ href: "https://host/book/chap1.mp3", type: "audio/mpeg" })];
    const resolved = resolveItemHrefs(items, readingOrder);
    expect(resolved[0].audioHref).toBe("https://host/book/chap1.mp3");
  });

  it("leaves item unchanged when no reading-order entry matches", () => {
    const items = [makeItem("missing.mp3", 0, 5)];
    const readingOrder = [new Link({ href: "https://host/book/chap1.mp3", type: "audio/mpeg" })];
    const resolved = resolveItemHrefs(items, readingOrder);
    expect(resolved[0].audioHref).toBe("missing.mp3");
  });

  it("resolves multiple items, each to their matching reading-order entry", () => {
    const items = [
      makeItem("chap1.mp3", 0, 5),
      makeItem("chap2.mp3", 0, 8),
    ];
    const readingOrder = [
      new Link({ href: "https://host/book/chap1.mp3", type: "audio/mpeg" }),
      new Link({ href: "https://host/book/chap2.mp3", type: "audio/mpeg" }),
    ];
    const resolved = resolveItemHrefs(items, readingOrder);
    expect(resolved[0].audioHref).toBe("https://host/book/chap1.mp3");
    expect(resolved[1].audioHref).toBe("https://host/book/chap2.mp3");
  });

  it("does not mutate the original items array", () => {
    const items = [makeItem("chap1.mp3", 0, 5)];
    const readingOrder = [new Link({ href: "https://host/book/chap1.mp3", type: "audio/mpeg" })];
    resolveItemHrefs(items, readingOrder);
    expect(items[0].audioHref).toBe("chap1.mp3");
  });

  it("returns an empty array for empty input", () => {
    expect(resolveItemHrefs([], [])).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// _buildAudioReadingOrder
// ---------------------------------------------------------------------------

describe("buildAudioReadingOrder", () => {
  it("returns one Link per unique audio file", () => {
    const items = [
      makeItem("chap1.mp3", 0, 5),
      makeItem("chap1.mp3", 5, 10),
      makeItem("chap2.mp3", 0, 8),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro).toHaveLength(2);
    expect(ro.map((l) => l.href)).toContain("https://host/book/chap1.mp3");
    expect(ro.map((l) => l.href)).toContain("https://host/book/chap2.mp3");
  });

  it("prefers the declared readingOrderDuration over the cue sum", () => {
    const items = [
      makeItem("chap1.mp3", 0, 5, { readingOrderDuration: 30 }),
      makeItem("chap1.mp3", 5, 10, { readingOrderDuration: 30 }),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].duration).toBe(30);
  });

  it("falls back to the cue sum when no readingOrderDuration is declared", () => {
    // cue sum: (5-0) + (10-5) = 10
    const items = [
      makeItem("chap1.mp3", 0, 5),
      makeItem("chap1.mp3", 5, 10),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].duration).toBe(10);
  });

  it("uses the maximum declared duration when multiple items for the same file have different readingOrderDuration values", () => {
    // Different values can appear when items come from different reading-order entries.
    const items = [
      makeItem("chap1.mp3", 0, 5, { readingOrderDuration: 20 }),
      makeItem("chap1.mp3", 5, 10, { readingOrderDuration: 30 }),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].duration).toBe(30);
  });

  it("resolves absolute hrefs when items already use full URLs", () => {
    const items = [makeItem("https://host/book/chap1.mp3", 0, 5)];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    // Already absolute → should not double-prepend the base URL.
    expect(ro[0].href).toBe("https://host/book/chap1.mp3");
  });

  it("resolves relative hrefs against the publication's self URL", () => {
    const items = [makeItem("chap1.mp3", 0, 5)];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].href).toBe("https://host/book/chap1.mp3");
  });

  it("uses the correct base URL (trailing slash after directory)", () => {
    const items = [makeItem("audio/chap1.mp3", 0, 5)];
    // self href ending in a filename → base is directory up to last '/'
    const pub = fakePub("https://cdn.example.com/pub/book1/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].href).toBe("https://cdn.example.com/pub/book1/audio/chap1.mp3");
  });

  it("preserves insertion order (first-appearance order)", () => {
    const items = [
      makeItem("chap2.mp3", 0, 5),
      makeItem("chap1.mp3", 0, 8),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].href).toContain("chap2.mp3");
    expect(ro[1].href).toContain("chap1.mp3");
  });

  it("sets the correct MIME type on each link", () => {
    const items = [
      makeItem("chap1.mp3", 0, 5),
      makeItem("chap2.ogg", 0, 8),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    const mp3 = ro.find((l) => l.href.endsWith("chap1.mp3"))!;
    const ogg = ro.find((l) => l.href.endsWith("chap2.ogg"))!;
    expect(mp3.type).toBe("audio/mpeg");
    expect(ogg.type).toBe("audio/ogg");
  });

  it("attaches the first tocTitle found for the file as link title", () => {
    const items = [
      makeItem("chap1.mp3", 0, 5, { tocTitle: "Chapter 1" }),
      makeItem("chap1.mp3", 5, 10, { tocTitle: "Chapter 1 continued" }),
    ];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].title).toBe("Chapter 1");
  });

  it("leaves duration undefined when cue sum is 0 and no readingOrderDuration", () => {
    // cues with null start/end contribute nothing to cueSum
    const items = [makeItem("chap1.mp3", null, null)];
    const pub = fakePub("https://host/book/manifest.json");
    const ro = buildAudioReadingOrder(items, pub);
    expect(ro[0].duration).toBeUndefined();
  });
});
