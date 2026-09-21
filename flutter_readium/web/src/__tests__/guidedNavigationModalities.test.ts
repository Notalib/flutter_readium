/**
 * Guided Navigation across every content modality the plugin ships.
 *
 * Each modality authors its cues differently, and a parser change that suits one shape
 * has silently dropped another before: a DiViNa comic references only the page image, so
 * requiring a `textref` produced zero cues and audio never started.
 */

import { Link, Links } from "@readium/shared";
import { parseGuidedNavigation } from "../mediaoverlay/guidedNavigation";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

const GUIDED_TYPE = "application/guided-navigation+json";

interface ReadingOrderSpec {
  href: string;
  title?: string;
  duration?: number;
  /** Guided document served as an alternate of this item (per-chapter authoring). */
  guided?: unknown;
}

/**
 * Builds a publication whose guided document(s) resolve to the supplied JSON.
 * `publicationGuided` puts a single document on `manifest.links` (Strategy 1);
 * a `guided` field on a reading-order item uses an alternate instead (Strategy 2).
 */
function makePublication(opts: {
  readingOrder: ReadingOrderSpec[];
  publicationGuided?: unknown;
}): ReadiumPublication {
  const documents = new Map<string, unknown>();
  const readingOrder: Link[] = [];

  opts.readingOrder.forEach((spec, index) => {
    const alternates: Link[] = [];
    if (spec.guided !== undefined) {
      const href = `guided-${index}.json`;
      documents.set(href, spec.guided);
      alternates.push(new Link({ href, type: GUIDED_TYPE }));
    }
    readingOrder.push(
      new Link({
        href: spec.href,
        title: spec.title,
        duration: spec.duration,
        alternates: alternates.length > 0 ? new Links(alternates) : undefined,
      })
    );
  });

  const links: Link[] = [];
  if (opts.publicationGuided !== undefined) {
    documents.set("guided-navigation.json", opts.publicationGuided);
    links.push(new Link({ href: "guided-navigation.json", type: GUIDED_TYPE }));
  }

  return {
    baseURL: "https://example.test/book/",
    readingOrder: { items: readingOrder },
    manifest: { links: links.length > 0 ? new Links(links) : undefined, toc: undefined },
    get: (link: Link) => ({
      readAsJSON: async () => {
        const key = link.href.split("/").pop() ?? link.href;
        return documents.get(key) ?? null;
      },
    }),
  } as unknown as ReadiumPublication;
}

describe("Guided Navigation — DiViNa comic (imgref only)", () => {
  /** Matches the shape of the `divina` test fixture: no text documents at all. */
  const divinaDocument = {
    guided: [
      {
        role: ["section"],
        children: [{ imgref: "cover.jpg", audioref: "01_cover.mp3#t=0,3.808" }],
      },
      {
        role: ["section"],
        children: [
          {
            imgref: "image0001.jpg#xywh=pixel:44,113,757,226",
            audioref: "02_side_1.mp3#t=0,12.5",
          },
          {
            imgref: "image0001.jpg#xywh=pixel:44,400,757,226",
            audioref: "02_side_1.mp3#t=12.5,25",
          },
        ],
      },
    ],
  };

  function divinaPublication(): ReadiumPublication {
    return makePublication({
      readingOrder: [
        { href: "cover.jpg", title: "Cover", duration: 3.808 },
        { href: "image0001.jpg", title: "Side 1", duration: 61.757 },
      ],
      publicationGuided: divinaDocument,
    });
  }

  it("produces one cue per imgref entry", async () => {
    const items = await parseGuidedNavigation(divinaPublication());
    expect(items).toHaveLength(3);
  });

  it("uses the page image as the cue's visual reference", async () => {
    const items = await parseGuidedNavigation(divinaPublication());
    expect(items.map((item) => item.textHref)).toEqual([
      "cover.jpg",
      "image0001.jpg",
      "image0001.jpg",
    ]);
    expect(items.every((item) => item.textId === "")).toBe(true);
  });

  it("derives the reading-order position and duration from the page image", async () => {
    const items = await parseGuidedNavigation(divinaPublication());
    expect(items.map((item) => item.position)).toEqual([0, 1, 1]);
    expect(items[1].readingOrderDuration).toBe(61.757);
  });

  it("keeps the panel region of each cue", async () => {
    const items = await parseGuidedNavigation(divinaPublication());
    expect(items[0].region).toBeUndefined();
    expect(items[1].region).toEqual({ x: 44, y: 113, w: 757, h: 226 });
    expect(items[2].region).toEqual({ x: 44, y: 400, w: 757, h: 226 });
  });

  it("reads the audio time range of each cue", async () => {
    const items = await parseGuidedNavigation(divinaPublication());
    expect(items[1].audioHref).toBe("02_side_1.mp3");
    expect(items[1].audioStart).toBe(0);
    expect(items[1].audioEnd).toBe(12.5);
  });
});

describe("Guided Navigation — comic with text documents (textref + imgref)", () => {
  it("keeps the text document as the reference and the image as the region", async () => {
    const publication = makePublication({
      readingOrder: [{ href: "page1.xhtml", title: "Side 1", duration: 30 }],
      publicationGuided: {
        guided: [
          {
            children: [
              {
                textref: "page1.xhtml#panel1",
                imgref: "image0001.jpg#xywh=pixel:10,20,30,40",
                audioref: "page1.mp3#t=0,5",
              },
            ],
          },
        ],
      },
    });

    const items = await parseGuidedNavigation(publication);
    expect(items).toHaveLength(1);
    expect(items[0].textHref).toBe("page1.xhtml");
    expect(items[0].textId).toBe("panel1");
    expect(items[0].region).toEqual({ x: 10, y: 20, w: 30, h: 40 });
  });
});

describe("Guided Navigation — EPUB (textref only)", () => {
  it("parses per-chapter alternates and leaves the region empty", async () => {
    const publication = makePublication({
      readingOrder: [
        { href: "chapter1.xhtml" },
        {
          href: "chapter2.xhtml",
          duration: 42,
          guided: {
            guided: [
              { textref: "chapter2.xhtml#p1", audioref: "chapter2.mp3#t=0,10" },
              { textref: "chapter2.xhtml#p2", audioref: "chapter2.mp3#t=10,20" },
            ],
          },
        },
      ],
    });

    const items = await parseGuidedNavigation(publication);
    expect(items).toHaveLength(2);
    expect(items[0].textHref).toBe("chapter2.xhtml");
    expect(items[0].textId).toBe("p1");
    expect(items[0].position).toBe(1);
    expect(items[0].readingOrderDuration).toBe(42);
    expect(items[0].region).toBeUndefined();
  });
});

describe("Guided Navigation — cues that cannot be played", () => {
  it("skips a cue with no visual reference at all", async () => {
    const publication = makePublication({
      readingOrder: [{ href: "image0001.jpg" }],
      publicationGuided: {
        guided: [{ children: [{ audioref: "a.mp3#t=0,5" }] }],
      },
    });

    expect(await parseGuidedNavigation(publication)).toHaveLength(0);
  });

  it("skips a cue with no audio", async () => {
    const publication = makePublication({
      readingOrder: [{ href: "image0001.jpg" }],
      publicationGuided: {
        guided: [{ children: [{ imgref: "image0001.jpg" }] }],
      },
    });

    expect(await parseGuidedNavigation(publication)).toHaveLength(0);
  });

  it("falls back to the first reading-order item when the reference is unknown", async () => {
    const publication = makePublication({
      readingOrder: [{ href: "image0001.jpg" }],
      publicationGuided: {
        guided: [{ children: [{ imgref: "missing.jpg", audioref: "a.mp3#t=0,5" }] }],
      },
    });

    const items = await parseGuidedNavigation(publication);
    expect(items).toHaveLength(1);
    expect(items[0].position).toBe(0);
    expect(items[0].readingOrderDuration).toBeUndefined();
  });
});
