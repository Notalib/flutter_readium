/**
 * Unit tests for mediaoverlay/uncuedTocTargets.ts: ToC entries that target an element the
 * Sync Narration does not list (the local-newspaper `<section>` / `<aside>` shape).
 */

import { getTime, Link, Links, Locator, LocatorLocations } from "@readium/shared";
import { SyncNarrationItem, parseSyncNarration, textLocatorToAudioLocator } from "../mediaoverlay/syncNarration";
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

  // `boundaryOwner` returns the index of the ToC id that replaces a cue's current owner, or undefined to keep it.
  // Only an element that encloses the cue and starts after the owner's element can replace it.
  it("uses enclosing later starts without extending headings or losing caller scope", () => {
    // Given: the shared tree at the top of this file.
    // Then: `p1` follows heading `h` in the same section, so the heading keeps it.
    expect(tree.boundaryOwner("p1", "h", ["sec", "h", "side", "sec2"])).toBeUndefined();
    // Then: `side` encloses `p2` and `sec2` encloses `p3`, and both start after `h`, so they take over.
    expect(tree.boundaryOwner("p2", "h", ["sec", "h", "side", "sec2"])).toBe(2);
    expect(tree.boundaryOwner("p3", "h", ["sec", "h", "side", "sec2"])).toBe(3);
    // Then: the owner `sec` already encloses `p1`, so no later boundary applies.
    expect(tree.boundaryOwner("p1", "sec", ["sec", "h", "side", "sec2"])).toBeUndefined();
    // Then: unknown ids and cues without an owner are left alone.
    expect(tree.boundaryOwner("p2", "missing", ["side"])).toBeUndefined();
    expect(tree.boundaryOwner("missing", "h", ["side"])).toBeUndefined();
    expect(tree.boundaryOwner("p1", undefined, ["h", "empty"])).toBeUndefined();
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

  it("leaves preludes unowned unless a file-only entry exists", () => {
    const items = cues();
    assignUncuedTocOwners(items, toc("side"), tree);
    expect(items.slice(0, 2).map((item) => item.tocHref)).toEqual([undefined, undefined]);
    assignUncuedTocOwners(items, [new Link({ href: "page.xhtml" }), ...toc("side")], tree);
    expect(items.slice(0, 2).map((item) => item.tocHref)).toEqual(["page.xhtml", "page.xhtml"]);
    expect(items[2].tocHref).toBe("page.xhtml#side");
  });

  it("keeps owners from the narration nesting", () => {
    const items = cues();
    items[1].tocHref = "page.xhtml#nested";
    assignUncuedTocOwners(items, toc("sec"), tree);
    expect(items[1].tocHref).toBe("page.xhtml#nested");
  });

  // A narrated heading must stop owning cues at a later XHTML ToC section that the narration never lists.
  // Otherwise playback reports the wrong section, and selecting that section in the ToC finds no cue.
  it("ends a narrated heading at the next XHTML section absent from narration", () => {
    // Given: narration only matches heading `h`, so `h` owns every cue. The XHTML puts `p2` in `side` and `p3` in `sec2`.
    const items = cues();
    items.forEach((item) => { item.tocHref = "page.xhtml#h"; });
    // When: owners are assigned from the XHTML.
    assignUncuedTocOwners(items, toc("sec", "h", "side", "sec2"), tree);
    // Then: `p1` stays with its heading, `side` and `sec2` take over their cues, and seeking `sec2` starts at `p3`.
    expect(items.map((item) => item.tocHref)).toEqual([
      "page.xhtml#h", "page.xhtml#h", "page.xhtml#side", "page.xhtml#sec2",
    ]);
    expect(getTime(textLocatorToAudioLocator(items, locator("sec2"), false, true)!.locations)).toBe(3);
  });

  // When the narration already lists a ToC container, the narration structure wins over the XHTML.
  // A cue that the narration places after the container must not be pulled into it.
  it("preserves the caller owner after a represented nested narration container", () => {
    // Given: narration owners put `p2` in `side` and `p3` back under `h`. The XHTML nests `p3` inside `side`.
    const items = [cue("h", 0, "page.xhtml#h"), cue("p2", 1, "page.xhtml#side"), cue("p3", 2, "page.xhtml#h")];
    const nestedTree = new XhtmlIdTree(el("sec", el("h"), el("side", el("p2"), el("p3"))));
    // When: owners are assigned from the XHTML.
    assignUncuedTocOwners(items, toc("sec", "h", "side"), nestedTree);
    // Then: `p3` keeps the owner from before the container (`h`).
    expect(items.map((item) => item.tocHref)).toEqual(["page.xhtml#h", "page.xhtml#side", "page.xhtml#h"]);
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

  // A narration container stays known even when a child heading owns all of its cues, so no cue owner shows it.
  // Otherwise the boundary correction treats it as missing and moves the cue after it into the container.
  // With `otherBoundary`, a real missing section `sec2` is still corrected in the same pass.
  it.each([false, true])("preserves a narration container hidden by its child heading (other boundary: %s)", async (otherBoundary) => {
    // Given: `side` contains narrated heading `sub`, so the cue owners never show `side`. The XHTML nests `p3`
    // inside `side`. Optionally, `p4` is in section `sec2`, which the narration never lists.
    const narrated = (id: string, start: number) => ({text: `page.xhtml#${id}`, audio: `page.mp3#t=${start},${start + 5}`});
    const narration = {narration: [narrated("h", 0),
      {text: "page.xhtml#side", narration: [narrated("sub", 5), narrated("p2", 10)]}, narrated("p3", 15),
      ...(otherBoundary ? [narrated("p4", 20)] : [])]};
    const links = toc("h", "side", "sub", ...(otherBoundary ? ["sec2"] : []));
    const publication = {
      baseURL: "https://example.test/book/",
      readingOrder: {items: [new Link({href: "page.xhtml", duration: 25,
        alternates: new Links([new Link({href: "sync.json", type: "application/vnd.readium.narration+json"})])})]},
      manifest: {toc: new Links(links)},
      get: () => ({readAsJSON: async () => narration, readAsString: async () => {reads++; return "<html/>";}}),
    } as unknown as ReadiumPublication;
    const dom = el("", el("h"), el("side", el("sub"), el("p2"), el("p3")),
      ...(otherBoundary ? [el("sec2", el("p4"))] : []));
    (globalThis as any).DOMParser = class {
      parseFromString() { return {getElementsByTagName: () => [], documentElement: dom}; }
    };
    const items = await parseSyncNarration(publication);
    // Then: parsing takes the owners from the narration.
    expect(items.slice(0, 4).map((item) => item.tocHref)).toEqual(toc("h", "sub", "sub", "h").map((link) => link.href));
    // When: owners are prepared, as during navigator initialization.
    await new UncuedTocTargets(publication, items, links).prepareOwners();
    // Then: `p3` is not moved into `side`, and only `p4` moves to `sec2`.
    expect(items.map((item) => item.tocHref)).toEqual(toc("h", "sub", "sub", "h", ...(otherBoundary ? ["sec2"] : [])).map((link) => link.href));
    expect(items.some((item) => item.tocHref === "page.xhtml#side")).toBe(false);
    expect(getTime(textLocatorToAudioLocator(items, locator("h"), false, true)!.locations)).toBe(0);
    if (otherBoundary) expect(getTime(textLocatorToAudioLocator(items, locator("sec2"), false, true)!.locations)).toBe(20);
    // Then: the XHTML is read only when a missing section can apply. A known container alone needs no read.
    expect(reads).toBe(otherBoundary ? 1 : 0);
  });

  it("anchors an uncued element to its first cue", async () => {
    const resolver = targets(cues(), toc("sec", "side"));
    expect(resolver.isUncued(locator("side"))).toBe(true);
    const anchored = await resolver.anchor(locator("side"));
    expect(anchored!.locations.fragments).toEqual(["p2"]);
    expect(anchored!.locations.otherLocations?.get("cssSelector")).toBe("#p2");
  });

  it("leaves cues and known ToC anchors unchanged and rejects elements after the last cue", async () => {
    const items = cues();
    items[0].tocHref = "page.xhtml#known";
    const resolver = targets(items, toc("sec"));
    expect(resolver.isUncued(locator("p1"))).toBe(false);
    expect(resolver.isUncued(locator("known"))).toBe(false);
    expect((await resolver.anchor(locator("p1")))!.locations.fragments).toEqual(["p1"]);
    expect((await resolver.anchor(locator("known")))!.locations.fragments).toEqual(["known"]);
    expect(await resolver.anchor(locator("empty"))).toBeUndefined();
  });

  it("keeps an uncued section seek stable after ownership is filled", async () => {
    const preludeRoot = el("", el("pre"), el("sec", el("p1"), el("p2")));
    (globalThis as any).DOMParser = class {
      parseFromString() {
        return { getElementsByTagName: () => [], documentElement: preludeRoot };
      }
    };
    const items = [cue("pre", 0), cue("p1", 1), cue("p2", 2)];
    const resolver = targets(items, toc("sec"));
    const seek = async () => getTime(textLocatorToAudioLocator(
      items, (await resolver.anchor(locator("sec")))!, false, true
    )!.locations);

    expect(await seek()).toBe(1);
    await resolver.fillOwners("page.xhtml");
    expect(await seek()).toBe(1);
  });

  it("seeks forward from a known element with no narrated descendant", async () => {
    const resolver = targets([cue("p1", 1), cue("p2", 2)], toc("h"));
    expect((await resolver.anchor(locator("h")))!.locations.fragments).toEqual(["p1"]);
    expect(await resolver.anchor(locator("missing"))).toEqual(locator("missing"));
  });

  it("preserves explicit time and non-anchor locator metadata", async () => {
    const resolver = targets(cues(), toc("side"));
    const timed = new Locator({ href: "page.xhtml", type: "application/xhtml+xml",
      locations: new LocatorLocations({ fragments: ["side", "t=2.5"] }) });
    expect(resolver.isUncued(timed)).toBe(false);
    expect(await resolver.anchor(timed)).toBe(timed);
    const input = new Locator({ href: "page.xhtml", type: "application/xhtml+xml", title: "Section",
      locations: new LocatorLocations({ fragments: ["side"], progression: 0.4, position: 3,
        otherLocations: new Map([["custom", "preserved"]]) }) });
    const anchored = (await resolver.anchor(input))!;
    expect(anchored.title).toBe("Section");
    expect(anchored.locations.progression).toBe(0.4);
    expect(anchored.locations.position).toBe(3);
    expect(anchored.locations.otherLocations?.get("custom")).toBe("preserved");
    expect(input.locations.fragments).toEqual(["side"]);
  });

  // The correction must finish before the first owner-based seek. Otherwise that seek can resolve against stale
  // owners, and the same request can land somewhere else later. Concurrent callers must share one XHTML read.
  it("awaits correction before the first owner-based seek and shares concurrent resource work", async () => {
    // Given: heading `h` owns every cue, although `p3` is in section `sec2`.
    const items = cues();
    items.forEach((item) => { item.tocHref = "page.xhtml#h"; });
    const resolver = targets(items, toc("sec", "h", "side", "sec2"));
    // When: two callers prepare the owners at the same time.
    await Promise.all([resolver.prepareOwners(), resolver.prepareOwners()]);
    // Then: `p3` is owned by `sec2`, seeking `sec2` starts at `p3`, and the XHTML was read once.
    expect(items[3].tocHref).toBe("page.xhtml#sec2");
    expect(getTime(textLocatorToAudioLocator(items, locator("sec2"), false, true)!.locations)).toBe(3);
    expect(reads).toBe(1);
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
