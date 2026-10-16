/** @jest-environment jsdom */
import { XhtmlIdTree } from "../mediaoverlay/uncuedTocTargets";

describe("XhtmlIdTree with the browser DOM parser", () => {
  it("parses namespaced XHTML and keeps subtree boundaries", () => {
    const tree = XhtmlIdTree.parse(`<html xmlns="http://www.w3.org/1999/xhtml"><body>
      <section id="section"><div><p id="cue">Text</p></div></section>
      <p id="outside">Next</p></body></html>`);
    expect(tree.ids).toEqual(["section", "cue", "outside"]);
    expect(tree.firstDescendant("section", new Set(["cue", "outside"]))).toBe("cue");
    expect(tree.firstDescendant("section", new Set(["outside"]))).toBeUndefined();
  });

  it("recovers ids after an undeclared XML entity by retrying as HTML", () => {
    const tree = XhtmlIdTree.parse(`<html><body><section id="section">
      <p id="before">Before &nbsp; space</p><p id="after">After</p></section></body></html>`);
    expect(tree.ids).toEqual(["section", "before", "after"]);
    expect(tree.firstDescendant("section", new Set(["after"]))).toBe("after");
  });
});
