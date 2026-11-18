/** @jest-environment jsdom */
import {
  injectDecorationOverrides,
  setSpotlightGroupOnIframes,
  clearSpotlightState,
} from "../decorations/decorationFrameUtils";

function makeFrame(): Window {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  return iframe.contentWindow!;
}

const spotlightCss = (wnd: Window) =>
  wnd.document.getElementById("flutter-readium-spotlight-style")?.textContent ?? "";

describe("spotlight frame dimming", () => {
  afterEach(() => {
    clearSpotlightState();
    document.body.innerHTML = "";
  });

  it("dims body text while any group is active and removes the dim when the last clears", () => {
    const wnd = makeFrame();

    setSpotlightGroupOnIframes([wnd], "a__spotlight", true);
    setSpotlightGroupOnIframes([wnd], "b__spotlight", true);
    expect(wnd.document.body.classList.contains("flutter-readium-spotlight")).toBe(true);
    expect(spotlightCss(wnd)).toContain("rgba(0, 0, 0, 0.22)");

    setSpotlightGroupOnIframes([wnd], "a__spotlight", false);
    expect(wnd.document.body.classList.contains("flutter-readium-spotlight")).toBe(true);

    setSpotlightGroupOnIframes([wnd], "b__spotlight", false);
    expect(wnd.document.body.classList.contains("flutter-readium-spotlight")).toBe(false);
    expect(spotlightCss(wnd)).toBe("");
  });

  it("re-applies an active spotlight to a frame that loads later, once", () => {
    setSpotlightGroupOnIframes([], "a__spotlight", true);
    const late = makeFrame();

    injectDecorationOverrides(late);
    expect(late.document.body.classList.contains("flutter-readium-spotlight")).toBe(true);

    // The injected flag makes a repeated frameLoaded a no-op, even after the spotlight is cleared.
    setSpotlightGroupOnIframes([late], "a__spotlight", false);
    injectDecorationOverrides(late);
    expect(late.document.body.classList.contains("flutter-readium-spotlight")).toBe(false);
  });
});
