/**
 * Unit tests for mediaoverlay/uncuedTocTargets.ts: ToC entries that target an element the
 * Sync Narration does not list (the local-newspaper `<section>` / `<aside>` shape).
 */

import { Link, Locator, LocatorLocations } from "@readium/shared";
import { SyncNarrationItem } from "../mediaoverlay/syncNarration";
import {
  IdTreeElement,
  UncuedTocTargets,
  XhtmlIdTree,
  assignUncuedTocOwners,
} from "../mediaoverlay/uncuedTocTargets";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

function el(id: string, ...children: IdTreeElement[]): IdTreeElement {
  return { id, children };
}

// <section id="sec"><h1 id="h"/><p id="p1"/><aside id="side"><span id="x"/><p id="p2"/></aside></section>
// <section id="sec2"><p id="p3"/></section><section id="empty"/>
const root = el(
  "",
  el(
    "",
    el("sec", el("h"), el("p1"), el("side", el("x"), el("p2"))),
    el("sec2", el("p3")),
    el("empty")
  )
);

function cue(textId: string, start: number, tocHref?: string): SyncNarrationItem {
  return {
    audio: `page.mp3#t=${start},${start + 1}`,
    text: `page.xhtml#${textId}`,
    position: 0,
    audioHref: "page.mp3",
    audioStart: start,
    audioEnd: start + 1,
    textHref: "page.xhtml",
    textId,
    tocHref,
  };
}

function cues(): SyncNarrationItem[] {
  return [cue("h", 0), cue("p1", 1), cue("p2", 2), cue("p3", 3)];
}

function toc(...ids: string[]): Link[] {
  return ids.map((id) => new Link({ href: `page.xhtml#${id}`, title: id }));
}

function locator(id: string): Locator {
  return new Locator({
    href: "page.xhtml",
    type: "application/xhtml+xml",
    locations: new LocatorLocations({ fragments: [id] }),
  });
}

describe("XhtmlIdTree", () => {
  const tree = new XhtmlIdTree(root);

  it("maps a container to its first candidate descendant", () => {
    expect(tree.firstDescendant("sec", new Set(["h", "p1", "p2"]))).toBe("h");
    expect(tree.firstDescendant("side", new Set(["h", "p1", "p2"]))).toBe("p2");
  });

  it("does not match the element itself or leak past its end", () => {
    expect(tree.firstDescendant("p1", new Set(["p1"]))).toBeUndefined();
    expect(tree.firstDescendant("side", new Set(["p3"]))).toBeUndefined();
  });

  it("returns undefined for empty or missing elements", () => {
    expect(tree.firstDescendant("empty", new Set(["p3"]))).toBeUndefined();
    expect(tree.firstDescendant("missing", new Set(["p3"]))).toBeUndefined();
  });
});

describe("assignUncuedTocOwners", () => {
  const tree = new XhtmlIdTree(root);

  it("gives each cue the ToC entry that precedes it in document order", () => {
    const items = cues();
    assignUncuedTocOwners(items, toc("sec", "side", "sec2"), tree);
    expect(items.map((item) => item.tocHref)).toEqual([
      "page.xhtml#sec",
      "page.xhtml#sec",
      "page.xhtml#side",
      "page.xhtml#sec2",
    ]);
    expect(items[2].tocTitle).toBe("side");
  });

  it("lets the deeper entry win when both start at the same cue", () => {
    const items = cues();
    assignUncuedTocOwners(items, toc("sec", "h"), tree);
    expect(items[0].tocHref).toBe("page.xhtml#h");
  });

  it("keeps owners from the narration nesting", () => {
    const items = cues();
    items[1].tocHref = "page.xhtml#nested";
    assignUncuedTocOwners(items, toc("sec"), tree);
    expect(items[1].tocHref).toBe("page.xhtml#nested");
  });

  it("assigns nothing when no entry resolves to a cue", () => {
    const items = cues();
    assignUncuedTocOwners(items, toc("empty"), tree);
    expect(items.every((item) => item.tocHref === undefined)).toBe(true);
  });
});

describe("UncuedTocTargets", () => {
  const originalDomParser = (globalThis as any).DOMParser;
  let reads = 0;

  beforeEach(() => {
    reads = 0;
    (globalThis as any).DOMParser = class {
      parseFromString() {
        return { getElementsByTagName: () => [], documentElement: root };
      }
    };
  });

  afterEach(() => {
    (globalThis as any).DOMParser = originalDomParser;
  });

  function targets(items: SyncNarrationItem[], links: Link[]): UncuedTocTargets {
    const publication = {
      readingOrder: { items: [new Link({ href: "page.xhtml" })] },
      get: () => ({
        readAsString: async () => {
          reads++;
          return "<html/>";
        },
      }),
    } as unknown as ReadiumPublication;
    return new UncuedTocTargets(publication, items, links);
  }

  it("anchors an uncued element to its first cue", async () => {
    const resolver = targets(cues(), toc("sec", "side"));
    expect(resolver.isUncued(locator("side"))).toBe(true);
    const anchored = await resolver.anchor(locator("side"));
    expect(anchored.locations.fragments).toEqual(["p2"]);
    expect(anchored.locations.otherLocations?.get("cssSelector")).toBe("#p2");
  });

  it("leaves cues, known ToC anchors and cue-less elements unchanged", async () => {
    const items = cues();
    items[0].tocHref = "page.xhtml#known";
    const resolver = targets(items, toc("sec"));
    expect(resolver.isUncued(locator("p1"))).toBe(false);
    expect(resolver.isUncued(locator("known"))).toBe(false);
    expect((await resolver.anchor(locator("p1"))).locations.fragments).toEqual(["p1"]);
    expect((await resolver.anchor(locator("known"))).locations.fragments).toEqual(["known"]);
    expect((await resolver.anchor(locator("empty"))).locations.fragments).toEqual(["empty"]);
  });

  it("fills owners once per resource and reads the XHTML once", async () => {
    const items = cues();
    const resolver = targets(items, toc("sec", "side", "sec2"));
    await resolver.fillOwners("page.xhtml");
    await resolver.fillOwners("page.xhtml");
    await resolver.anchor(locator("side"));
    expect(items.map((item) => item.tocHref)).toEqual([
      "page.xhtml#sec",
      "page.xhtml#sec",
      "page.xhtml#side",
      "page.xhtml#sec2",
    ]);
    expect(reads).toBe(1);
  });
});
