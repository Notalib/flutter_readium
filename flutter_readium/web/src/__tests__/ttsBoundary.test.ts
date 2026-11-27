import {
  Body,
  getCssSelector,
  Locator,
  LocatorLocations,
  LocatorText,
  TextElement,
  TextSegment,
} from "@readium/shared";
import {
  segmentLocatorForCharIndex,
  wordLocatorForCharIndex,
} from "../navigators/ttsBoundary";

/**
 * Builds a segment the way HTMLResourceContentIterator does: leading and
 * trailing whitespace moves from `text.highlight` into `before` / `after`.
 */
function segment(text: string, selector: string, before = ""): TextSegment {
  const leading = text.match(/^\s*/)![0];
  const trailing = text.match(/\s*$/)![0];
  return new TextSegment(
    new Locator({
      href: "chap1.html",
      type: "text/html",
      locations: new LocatorLocations({ otherLocations: new Map([["cssSelector", selector]]) }),
      text: new LocatorText({ before: before + leading, highlight: text.trim(), after: trailing }),
    }),
    text
  );
}

function element(...segments: TextSegment[]): TextElement {
  return new TextElement(new Locator({ href: "chap1.html", type: "text/html" }), Body, segments);
}

// "Hello brave " + "new" + " world." — spoken as "Hello brave new world."
const multi = element(
  segment("Hello brave ", "p", "Title. "),
  segment("new", "p > em"),
  segment(" world.", "p")
);

describe("wordLocatorForCharIndex", () => {
  it("highlights the first word of the utterance", () => {
    const loc = wordLocatorForCharIndex(multi, 0, 5)!;
    expect(loc.text?.highlight).toBe("Hello");
    expect(loc.text?.before).toBe("Title. ");
    expect(loc.text?.after).toBe(" brave new world.");
  });

  it("highlights a word ending at the end of its segment", () => {
    const loc = wordLocatorForCharIndex(multi, 6, 5)!;
    expect(loc.text?.highlight).toBe("brave");
    expect(loc.text?.before).toBe("Title. Hello ");
  });

  it("maps an index in a later segment without drifting", () => {
    const loc = wordLocatorForCharIndex(multi, 12, 3)!;
    expect(loc.text?.highlight).toBe("new");
    expect(getCssSelector(loc.locations)).toBe("p > em");
    expect(loc.text?.after).toBe(" world.");
  });

  it("anchors a segment's leading whitespace only once", () => {
    const loc = wordLocatorForCharIndex(multi, 16, 6)!;
    expect(loc.text?.highlight).toBe("world.");
    expect(loc.text?.before).toBe(" ");
    expect(loc.text?.after).toBe("");
  });

  it("extends to the next whitespace when charLength is 0", () => {
    expect(wordLocatorForCharIndex(multi, 6, 0)?.text?.highlight).toBe("brave");
    expect(wordLocatorForCharIndex(multi, 16, 0)?.text?.highlight).toBe("world.");
  });

  it("skips whitespace reported before the word", () => {
    expect(wordLocatorForCharIndex(multi, 5, 0)?.text?.highlight).toBe("brave");
  });

  it("cuts a word at the end of its segment", () => {
    const split = element(segment("Hel", "p > b"), segment("lo there", "p"));
    expect(wordLocatorForCharIndex(split, 0, 5)?.text?.highlight).toBe("Hel");
  });

  it("returns null past the end of the text or without segments", () => {
    expect(wordLocatorForCharIndex(multi, 22, 0)).toBeNull();
    expect(wordLocatorForCharIndex(element(), 0, 3)).toBeNull();
  });

  it("caps the context on both sides", () => {
    const long = element(segment(`${"a ".repeat(40)}word ${"b ".repeat(40)}`, "p"));
    const loc = wordLocatorForCharIndex(long, 80, 4)!;
    expect(loc.text?.highlight).toBe("word");
    expect(loc.text?.before?.length).toBe(50);
    expect(loc.text?.after?.length).toBe(50);
  });
});

describe("segmentLocatorForCharIndex", () => {
  it("returns the segment containing the index", () => {
    expect(segmentLocatorForCharIndex(multi, 0)).toBe(multi.segments[0].locator);
    expect(segmentLocatorForCharIndex(multi, 12)).toBe(multi.segments[1].locator);
    expect(segmentLocatorForCharIndex(multi, 15)).toBe(multi.segments[2].locator);
  });

  it("falls back to the element locator outside the text", () => {
    expect(segmentLocatorForCharIndex(multi, 99)).toBe(multi.locator);
  });
});
