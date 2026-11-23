/**
 * Unit tests for the reading positions TTS starts from.
 *
 * The node test environment has no layout, so elements are fakes with fixed
 * client rects in a 100x100 frame viewport. Paginated EPUBs lay columns out
 * side by side, so earlier pages sit at negative x.
 */
import { Locator, LocatorLocations } from "@readium/shared";
import {
  bodyPathSelector,
  findFirstVisibleElement,
  withFirstVisibleElement,
  withQueryableCssSelector,
} from "../navigators/firstVisibleLocator";

interface FakeElement {
  tagName: string;
  nodeName: string;
  nodeType: number;
  id: string;
  textContent: string;
  previousSibling: FakeElement | null;
  parentElement: FakeElement | null;
  firstElementChild: FakeElement | null;
  nextElementSibling: FakeElement | null;
  previousElementSibling: FakeElement | null;
  getBoundingClientRect: () => { left: number; right: number; top: number; bottom: number; width: number; height: number };
}

function el(tagName: string, id: string, x: [number, number], children: FakeElement[] = []): FakeElement {
  const [left, right] = x;
  const element: FakeElement = {
    tagName,
    nodeName: tagName,
    nodeType: 1,
    id,
    textContent: id,
    previousSibling: null,
    parentElement: null,
    firstElementChild: children[0] ?? null,
    nextElementSibling: null,
    previousElementSibling: null,
    getBoundingClientRect: () => ({ left, right, top: 0, bottom: 50, width: right - left, height: 50 }),
  };
  children.forEach((child, i) => {
    child.parentElement = element;
    child.previousElementSibling = children[i - 1] ?? null;
    child.previousSibling = child.previousElementSibling;
    child.nextElementSibling = children[i + 1] ?? null;
  });
  return element;
}

function frame(body: FakeElement): Window {
  return { innerWidth: 100, innerHeight: 100, document: { body } } as unknown as Window;
}

function firstVisibleId(wnd: Window): string | undefined {
  return (findFirstVisibleElement(wnd, wnd.document.body) as unknown as FakeElement | undefined)?.id;
}

const chapter = new Locator({
  href: "chap1.html",
  type: "application/xhtml+xml",
  locations: new LocatorLocations({ progression: 0.4 }),
});

describe("findFirstVisibleElement", () => {
  it("skips blocks on earlier pages", () => {
    const wnd = frame(el("BODY", "body", [-200, 100], [
      el("P", "p1", [-200, -100]),
      el("P", "p2", [10, 90]),
    ]));

    expect(firstVisibleId(wnd)).toBe("p2");
  });

  it("starts at a paragraph continued from the previous page", () => {
    const wnd = frame(el("BODY", "body", [-200, 100], [
      el("P", "p1", [-200, -100]),
      el("P", "p2", [-50, 40], [el("SPAN", "s1", [-50, -10]), el("SPAN", "s2", [0, 40])]),
    ]));

    expect(firstVisibleId(wnd)).toBe("p2");
  });

  it("descends into a partly visible section", () => {
    const wnd = frame(el("BODY", "body", [-200, 100], [
      el("SECTION", "sec", [-200, 100], [el("P", "p1", [-200, -100]), el("P", "p2", [10, 90])]),
    ]));

    expect(firstVisibleId(wnd)).toBe("p2");
  });

  it("ignores inline and hidden elements", () => {
    const hidden = el("DIV", "hidden", [0, 0]);
    // A zero-size rect is how a display:none element reports.
    hidden.getBoundingClientRect = () => ({ left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0 });
    const wnd = frame(el("BODY", "body", [0, 100], [el("SPAN", "pagebreak", [0, 10]), hidden, el("P", "p1", [10, 90])]));

    expect(firstVisibleId(wnd)).toBe("p1");
  });
});

describe("bodyPathSelector", () => {
  it("lists child positions from the body down", () => {
    const target = el("P", "p2", [0, 1]);
    el("BODY", "body", [0, 1], [el("SECTION", "sec", [0, 1], [el("HGROUP", "h", [0, 1]), target])]);

    expect(bodyPathSelector(target as unknown as Element)).toBe("body > :nth-child(1) > :nth-child(2)");
  });
});

describe("withFirstVisibleElement", () => {
  it("adds the first visible element's selector to the reader's locator", () => {
    const wnd = frame(el("BODY", "body", [-200, 100], [el("P", "p1", [-200, -100]), el("P", "p2", [10, 90])]));

    const result = withFirstVisibleElement(chapter, [wnd]);

    expect(result.href).toBe("chap1.html");
    expect(result.locations.progression).toBeUndefined();
    expect(result.locations.otherLocations?.get("cssSelector")).toBe("body > :nth-child(2)");
  });

  it("adds no selector for the first content of the resource", () => {
    // The iterator would start after the section's first paragraph here.
    const wnd = frame(el("BODY", "body", [0, 100], [el("SECTION", "sec", [0, 100], [el("P", "p1", [10, 90])])]));

    const result = withFirstVisibleElement(chapter, [wnd]);

    expect(result.locations.otherLocations?.get("cssSelector")).toBeUndefined();
    expect(result.locations.progression).toBeUndefined();
  });

  it("keeps a selector the locator already has", () => {
    const precise = chapter.copyWithLocations({ otherLocations: new Map([["cssSelector", "#keep"]]) });
    const wnd = frame(el("BODY", "body", [0, 100], [el("P", "p1", [10, 90])]));

    expect(withFirstVisibleElement(precise, [wnd])).toBe(precise);
  });

  it("returns the locator unchanged when the frame cannot be inspected", () => {
    const empty = frame(el("BODY", "body", [0, 100]));
    const destroyed = {
      get document(): Document {
        throw new Error("frame destroyed");
      },
    } as unknown as Window;

    expect(withFirstVisibleElement(chapter, [destroyed])).toBe(chapter);
    expect(withFirstVisibleElement(chapter, [empty])).toBe(chapter);
  });

  it("leaves a fixed-layout spread alone, whose frames show other resources", () => {
    const page = () => frame(el("BODY", "body", [0, 100], [el("P", "p1", [10, 90])]));

    expect(withFirstVisibleElement(chapter, [page(), page()])).toBe(chapter);
  });
});

describe("withQueryableCssSelector", () => {
  const withSelector = (cssSelector: string) =>
    chapter.copyWithLocations({ otherLocations: new Map([["cssSelector", cssSelector]]) });

  it("anchors the iterator's document-relative selectors at the root element", () => {
    const result = withQueryableCssSelector(withSelector(":scope > :nth-child(1) > :nth-child(2) > :nth-child(1)"));

    expect(result.locations.otherLocations?.get("cssSelector")).toBe(":root > :nth-child(2) > :nth-child(1)");
  });

  it("leaves other selectors alone", () => {
    const locator = withSelector("hgroup p");
    const fromElsewhere = withSelector(":scope > body > p");

    expect(withQueryableCssSelector(locator)).toBe(locator);
    expect(withQueryableCssSelector(fromElsewhere)).toBe(fromElsewhere);
    expect(withQueryableCssSelector(chapter)).toBe(chapter);
  });
});
