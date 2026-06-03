/**
 * Unit tests for the Guided Navigation parser.
 *
 * Tests the pure JSON-layer functions exposed via `__testing__`, plus the
 * shared `enrichItemsWithToc` helper from syncNarration. The publication-aware
 * detect/parse entry points are not covered here — those would require mocking
 * `Resource.readAsJSON` and the full `ReadiumPublication` fetcher.
 */

import { __testing__ } from "../Audio/guidedNavigation";
import {
  enrichItemsWithToc,
  parseAudioField,
  parseTextField,
  SyncNarrationItem,
} from "../Audio/syncNarration";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

const { parseDocument, parseObject } = __testing__;

// ---------------------------------------------------------------------------
// Fake publication builders
//
// The parser duck-types its publication argument (only `.manifest.toc?.items`
// and a few Link fields are read). These helpers construct just enough shape
// to drive the enrichment logic without pulling in real @readium/shared
// publication construction.
// ---------------------------------------------------------------------------

interface FakeLink {
  href: string;
  title?: string;
  duration?: number;
  children?: { items: FakeLink[] };
}

function makeFakePublication(opts: { toc?: FakeLink[] } = {}): ReadiumPublication {
  return {
    manifest: {
      toc: opts.toc ? { items: opts.toc } : undefined,
    },
  } as unknown as ReadiumPublication;
}

// ---------------------------------------------------------------------------
// parseAudioField
// ---------------------------------------------------------------------------

describe("parseAudioField", () => {
  it("parses href + start + end", () => {
    expect(parseAudioField("chap.mp3#t=12.34,15.67")).toEqual({
      audioHref: "chap.mp3",
      audioStart: 12.34,
      audioEnd: 15.67,
    });
  });

  it("parses href + start only (open-ended cue)", () => {
    expect(parseAudioField("chap.mp3#t=12.5")).toEqual({
      audioHref: "chap.mp3",
      audioStart: 12.5,
      audioEnd: null,
    });
  });

  it("returns nulls when no time fragment is present", () => {
    expect(parseAudioField("chap.mp3")).toEqual({
      audioHref: "chap.mp3",
      audioStart: null,
      audioEnd: null,
    });
  });

  it("returns nulls when the fragment is not a time fragment", () => {
    expect(parseAudioField("chap.mp3#section1")).toEqual({
      audioHref: "chap.mp3",
      audioStart: null,
      audioEnd: null,
    });
  });
});

// ---------------------------------------------------------------------------
// parseTextField
// ---------------------------------------------------------------------------

describe("parseTextField", () => {
  it("splits href and fragment id", () => {
    expect(parseTextField("chap.html#p001")).toEqual({
      textHref: "chap.html",
      textId: "p001",
    });
  });

  it("returns empty textId when no fragment is present", () => {
    expect(parseTextField("chap.html")).toEqual({
      textHref: "chap.html",
      textId: "",
    });
  });
});

// ---------------------------------------------------------------------------
// parseDocument / parseObject
// ---------------------------------------------------------------------------

describe("parseDocument", () => {
  it("returns null for null input", () => {
    expect(parseDocument(null)).toBeNull();
  });

  it("returns null when guided field is missing", () => {
    expect(parseDocument({})).toBeNull();
  });

  it("returns null when guided is an empty array", () => {
    expect(parseDocument({ guided: [] })).toBeNull();
  });

  it("returns null when guided contains only invalid entries", () => {
    expect(parseDocument({ guided: [null, "not an object", 42] })).toBeNull();
  });

  it("parses a single object with audioref + textref", () => {
    const doc = parseDocument({
      guided: [{ audioref: "a.mp3#t=0,1", textref: "a.html#p1" }],
    });
    expect(doc).not.toBeNull();
    expect(doc!.guided).toHaveLength(1);
    expect(doc!.guided[0].audioref).toBe("a.mp3#t=0,1");
    expect(doc!.guided[0].textref).toBe("a.html#p1");
    expect(doc!.guided[0].children).toEqual([]);
  });

  it("parses nested children recursively", () => {
    const doc = parseDocument({
      guided: [
        {
          audioref: "a.mp3#t=0,1",
          textref: "a.html",
          children: [
            { audioref: "a.mp3#t=1,2", textref: "a.html#p2" },
          ],
        },
      ],
    });
    expect(doc).not.toBeNull();
    expect(doc!.guided[0].children).toHaveLength(1);
    expect(doc!.guided[0].children[0].audioref).toBe("a.mp3#t=1,2");
  });

  it("skips invalid children but keeps valid siblings", () => {
    const doc = parseDocument({
      guided: [
        { audioref: "a.mp3#t=0,1", textref: "a.html#p1" },
        null,
        { audioref: "a.mp3#t=1,2", textref: "a.html#p2" },
      ],
    });
    expect(doc).not.toBeNull();
    expect(doc!.guided).toHaveLength(2);
  });
});

describe("parseObject", () => {
  it("returns null for null", () => {
    expect(parseObject(null)).toBeNull();
  });

  it("returns null for primitive input", () => {
    expect(parseObject(42)).toBeNull();
    expect(parseObject("a string")).toBeNull();
  });

  it("returns null for an object with no usable fields", () => {
    expect(parseObject({ role: ["heading"] })).toBeNull();
  });

  it("accepts an object with only children (no own refs)", () => {
    const obj = parseObject({
      children: [{ audioref: "a.mp3#t=0,1", textref: "a.html#p1" }],
    });
    expect(obj).not.toBeNull();
    expect(obj!.audioref).toBeUndefined();
    expect(obj!.textref).toBeUndefined();
    expect(obj!.children).toHaveLength(1);
  });

  it("ignores non-string audioref / textref", () => {
    const obj = parseObject({ audioref: 12, textref: ["wrong"] });
    expect(obj).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// enrichItemsWithToc
// ---------------------------------------------------------------------------

describe("enrichItemsWithToc", () => {
  function makeItem(text: string, textHref = text.split("#")[0]): SyncNarrationItem {
    return {
      audio: "a.mp3#t=0,1",
      text,
      position: 1,
      audioHref: "a.mp3",
      audioStart: 0,
      audioEnd: 1,
      textHref,
      textId: text.split("#")[1] ?? "",
    };
  }

  it("returns items unchanged when publication has no ToC", () => {
    const items = [makeItem("c1.html#p1")];
    const out = enrichItemsWithToc(items, makeFakePublication());
    expect(out).toEqual(items);
  });

  it("attaches tocTitle/tocHref on exact href match", () => {
    const pub = makeFakePublication({
      toc: [{ href: "c1.html#p1", title: "Section 1.1" }],
    });
    const items = [makeItem("c1.html#p1")];
    const out = enrichItemsWithToc(items, pub);
    expect(out[0].tocTitle).toBe("Section 1.1");
    expect(out[0].tocHref).toBe("c1.html#p1");
  });

  it("inherits from the last matched entry when textFile matches (sliding window)", () => {
    const pub = makeFakePublication({
      toc: [{ href: "c1.html#start", title: "Chapter 1" }],
    });
    const items = [makeItem("c1.html#start"), makeItem("c1.html#p2"), makeItem("c1.html#p3")];
    const out = enrichItemsWithToc(items, pub);
    expect(out[0].tocTitle).toBe("Chapter 1");
    expect(out[1].tocTitle).toBe("Chapter 1");
    expect(out[2].tocTitle).toBe("Chapter 1");
  });

  it("does not inherit across files", () => {
    const pub = makeFakePublication({
      toc: [{ href: "c1.html#start", title: "Chapter 1" }],
    });
    const items = [makeItem("c1.html#start"), makeItem("c2.html#p1")];
    const out = enrichItemsWithToc(items, pub);
    expect(out[0].tocTitle).toBe("Chapter 1");
    expect(out[1].tocTitle).toBeUndefined();
  });

  it("flattens nested ToC entries recursively", () => {
    const pub = makeFakePublication({
      toc: [
        {
          href: "c1.html",
          title: "Chapter 1",
          children: { items: [{ href: "c1.html#s1", title: "Section 1.1" }] },
        },
      ],
    });
    const items = [makeItem("c1.html#s1")];
    const out = enrichItemsWithToc(items, pub);
    expect(out[0].tocTitle).toBe("Section 1.1");
  });
});
