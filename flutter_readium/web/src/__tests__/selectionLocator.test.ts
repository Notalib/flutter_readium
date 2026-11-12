/** @jest-environment jsdom */
import { Locator, LocatorLocations } from "@readium/shared";
import { BasicTextSelection } from "@readium/navigator-html-injectables";
import {
  buildSelectionLocator,
  buildTextSelectionPayload,
  findSelectionFrame,
} from "../navigators/navigatorUtils";

const current = new Locator({
  href: "ch1.xhtml",
  type: "application/xhtml+xml",
  title: "Chapter 1",
  locations: new LocatorLocations({ progression: 0.25, position: 3 }),
});

function selectionOf(text: string, extra: Partial<BasicTextSelection> = {}): BasicTextSelection {
  return { text, x: 0, y: 0, width: 1, height: 1, targetFrameSrc: "about:blank", ...extra };
}

/** A frame whose body is `html`, with `needle` (the nth occurrence) selected. */
function frameSelecting(html: string, needle: string, occurrence: number): Window {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  const wnd = iframe.contentWindow!;
  wnd.document.body.innerHTML = html;

  const walker = wnd.document.createTreeWalker(wnd.document.body, NodeFilter.SHOW_TEXT);
  let seen = 0;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    let from = 0;
    for (;;) {
      const at = node.textContent!.indexOf(needle, from);
      if (at < 0) break;
      if (seen++ === occurrence) {
        const range = wnd.document.createRange();
        range.setStart(node, at);
        range.setEnd(node, at + needle.length);
        wnd.getSelection()!.removeAllRanges();
        wnd.getSelection()!.addRange(range);
        return wnd;
      }
      from = at + needle.length;
    }
  }
  throw new Error("needle not found");
}

describe("buildSelectionLocator", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("adds the surrounding text of the selected occurrence", () => {
    const wnd = frameSelecting("<p>the cat sat. The cat ran away from the dog.</p>", "cat", 1);

    const locator = buildSelectionLocator(current, selectionOf("cat"), wnd);

    expect(locator.text?.highlight).toBe("cat");
    expect(locator.text?.before).toBe("the cat sat. The ");
    expect(locator.text?.after).toBe(" ran away from the dog.");
  });

  it("limits context to 64 characters on each side", () => {
    const long = "x".repeat(200);
    const wnd = frameSelecting(`<p>${long}needle${long}</p>`, "needle", 0);

    const locator = buildSelectionLocator(current, selectionOf("needle"), wnd);

    expect(locator.text?.before).toBe("x".repeat(64));
    expect(locator.text?.after).toBe("x".repeat(64));
  });

  it("measures context across element boundaries", () => {
    const wnd = frameSelecting("<p>Alpha <b>beta</b> gamma</p><p>delta</p>", "gamma", 0);

    const locator = buildSelectionLocator(current, selectionOf("gamma"), wnd);

    expect(locator.text?.before).toBe("Alpha beta ");
    expect(locator.text?.after).toBe("delta");
  });

  it("takes href and type from the frame that reported the selection", () => {
    const fromSecondPage = new Locator({ href: "ch2.xhtml", type: "text/html" });

    const locator = buildSelectionLocator(current, selectionOf("w", { locator: fromSecondPage }));

    expect(locator.href).toBe("ch2.xhtml");
    expect(locator.type).toBe("text/html");
    // Page-level locations of the current resource do not describe the other page.
    expect(locator.title).toBeUndefined();
    expect(locator.locations.progression).toBeUndefined();
  });

  it("keeps the current locator's title and locations for the same resource", () => {
    const locator = buildSelectionLocator(
      current,
      selectionOf("w", { locator: new Locator({ href: "ch1.xhtml", type: "text/html" }) })
    );

    expect(locator.title).toBe("Chapter 1");
    expect(locator.locations.progression).toBe(0.25);
  });

  it("falls back to the current locator without a frame", () => {
    const locator = buildSelectionLocator(current, selectionOf("word"));

    expect(locator.href).toBe("ch1.xhtml");
    expect(locator.text?.highlight).toBe("word");
    expect(locator.text?.before).toBeUndefined();
  });
});

describe("buildTextSelectionPayload", () => {
  it("serializes the locator and echoes the selected text", () => {
    const locator = buildSelectionLocator(current, selectionOf("word"));

    expect(JSON.parse(buildTextSelectionPayload(locator, "word"))).toEqual({
      locator: locator.serialize(),
      selectedText: "word",
    });
  });
});

describe("findSelectionFrame", () => {
  it("matches the frame by its document URL and tolerates destroyed frames", () => {
    const iframeA = document.createElement("iframe");
    const iframeB = document.createElement("iframe");
    document.body.appendChild(iframeA);
    document.body.appendChild(iframeB);
    const destroyed = {
      get window(): Window {
        throw new Error("destroyed");
      },
      iframe: iframeA,
    };
    const nav = {
      _cframes: [
        undefined,
        destroyed,
        { window: iframeA.contentWindow!, iframe: iframeA },
        { window: iframeB.contentWindow!, iframe: iframeB },
      ],
    };

    // Both are about:blank here, so the first live match wins.
    expect(findSelectionFrame(nav, "about:blank")?.iframe).toBe(iframeA);
    expect(findSelectionFrame(nav, "https://nope/")).toBeUndefined();
    expect(findSelectionFrame(nav, undefined)).toBeUndefined();
  });
});
