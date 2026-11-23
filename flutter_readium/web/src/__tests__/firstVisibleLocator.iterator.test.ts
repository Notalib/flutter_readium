/**
 * @jest-environment jsdom
 *
 * Feeds the start position TTS computes from a rendered page to the toolkit's
 * real content iterator, which parses its own copy of the resource.
 */
import { HTMLResourceContentIterator, Locator, LocatorLocations, TextElement } from "@readium/shared";
import { withFirstVisibleElement } from "../navigators/firstVisibleLocator";

// jsdom has no CSS.escape, which the iterator's selector generator calls.
(globalThis as { CSS?: unknown }).CSS ??= { escape: (value: string) => value.replace(/[^\w-]/g, "\\$&") };

/** Elements whose id is in `visible` lie inside the viewport; the rest lie on the previous page. */
function renderedFrame(html: string, visible: string[]): Window {
  const doc = new DOMParser().parseFromString(html, "application/xhtml+xml");
  for (const element of Array.from(doc.querySelectorAll("*"))) {
    const left = visible.includes(element.id) || element.tagName === "body" ? 10 : -200;
    element.getBoundingClientRect = () => ({ left, right: left + 80, top: 0, bottom: 50, width: 80, height: 50 }) as DOMRect;
  }
  // A wrapper reaches back to the previous page when a child lies there.
  for (const element of Array.from(doc.querySelectorAll("[data-spans]"))) {
    element.getBoundingClientRect = () => ({ left: -200, right: 90, top: 0, bottom: 50, width: 290, height: 50 }) as DOMRect;
  }
  return { innerWidth: 100, innerHeight: 100, document: doc } as unknown as Window;
}

async function firstSpokenText(html: string, visible: string[]): Promise<string> {
  const chapter = new Locator({
    href: "chap.xhtml",
    type: "application/xhtml+xml",
    locations: new LocatorLocations({ progression: 0.5 }),
  });
  const start = withFirstVisibleElement(chapter, [renderedFrame(html, visible)]);
  const resource = { readAsString: async () => html };
  const iterator = new HTMLResourceContentIterator(resource as never, start);
  if (!(await iterator.hasNext())) return "";
  return (iterator.next() as TextElement).segments.map((segment) => segment.text).join("");
}

const xhtml = (body: string) => `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>${body}</body></html>`;

describe("TTS start position with the toolkit iterator", () => {
  it("starts at the first paragraph of a fully visible section", async () => {
    const html = xhtml(`<h1 id="h">Title</h1><section id="s"><p id="p1">One</p><p id="p2">Two</p></section>`);

    expect(await firstSpokenText(html, ["s", "p1", "p2"])).toBe("One");
  });

  it("reads a chapter that is a single wrapped paragraph", async () => {
    const html = xhtml(`<section id="s"><p id="p1">Only</p></section>`);

    expect(await firstSpokenText(html, ["s", "p1"])).toBe("Only");
  });

  it("ignores a comment before a chapter that is a single wrapped paragraph", async () => {
    const html = xhtml(`<!-- page 12 --><section id="s"><p id="p1">Only</p></section>`);

    expect(await firstSpokenText(html, ["s", "p1"])).toBe("Only");
  });

  it("starts at the first visible paragraph of a section continued from the previous page", async () => {
    const html = xhtml(`<section id="s" data-spans="1"><p id="p1">One</p><p id="p2">Two</p></section>`);

    expect(await firstSpokenText(html, ["p2"])).toBe("Two");
  });

  it("keeps a section's own text before its first paragraph", async () => {
    const html = xhtml(`<h1 id="h">Title</h1><div id="d">Intro <p id="p1">One</p></div>`);

    expect(await firstSpokenText(html, ["d", "p1"])).toBe("Intro");
  });
});
