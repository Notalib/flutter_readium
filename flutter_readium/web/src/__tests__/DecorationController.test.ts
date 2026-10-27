import { Locator, LocatorLocations } from "@readium/shared";
import { DecorationController } from "../decorations/DecorationController";

const mockNavIframeWindows = jest.fn((_nav: unknown): Window[] => []);
const mockSetSpotlightGroupOnIframes = jest.fn(
  (_iframes: Window[], _group: string, _active: boolean): void => {}
);
const mockClearSpotlightState = jest.fn();

jest.mock("../decorations/decorationFrameUtils", () => ({
  SPOTLIGHT_GROUP_SUFFIX: "__spotlight",
  navIframeWindows: (nav: unknown) => mockNavIframeWindows(nav),
  setSpotlightGroupOnIframes: (iframes: Window[], group: string, active: boolean) =>
    mockSetSpotlightGroupOnIframes(iframes, group, active),
  clearSpotlightState: () => mockClearSpotlightState(),
}));

const locator = new Locator({
  href: "chapter-1.xhtml",
  type: "application/xhtml+xml",
  locations: new LocatorLocations({ fragments: ["p1"] }),
});

function item(id: string, style: string, tint = "#ccfdff00") {
  return { id, locator: locator.serialize(), style: { style, tint } };
}

function makeNav() {
  return {
    applyDecorations: jest.fn(),
    registerDecorationObserver: jest.fn(),
  };
}

function setup() {
  const bridge = { emitDecorationInteraction: jest.fn() };
  const controller = new DecorationController(bridge);
  const nav = makeNav();
  return { bridge, controller, nav };
}

/** The decorations passed to `nav.applyDecorations` for one upstream (sub)group. */
function appliedTo(nav: ReturnType<typeof makeNav>, group: string): any[] {
  const call = nav.applyDecorations.mock.calls.find(([, g]) => g === group);
  return call ? call[0] : [];
}

describe("DecorationController", () => {
  beforeEach(() => {
    mockNavIframeWindows.mockClear();
    mockSetSpotlightGroupOnIframes.mockClear();
    mockClearSpotlightState.mockClear();
  });

  describe("applying decorations", () => {
    it("converts Dart tints and disables contrast enforcement", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "tts_utterance", JSON.stringify([item("dec-1", "highlight")]));

      expect(appliedTo(nav, "tts_utterance")).toEqual([
        expect.objectContaining({
          id: "dec-1",
          style: expect.objectContaining({ tint: "#fdff00cc", enforceContrast: false }),
        }),
      ]);
    });

    it("keeps highlight and underline in the group and routes spotlight to its subgroup", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(
        nav as any,
        "notes",
        JSON.stringify([item("h", "highlight"), item("u", "underline"), item("s", "spotlight")])
      );

      expect(nav.applyDecorations).toHaveBeenCalledTimes(2);
      expect(appliedTo(nav, "notes").map((d) => d.id)).toEqual(["h", "u"]);
      expect(appliedTo(nav, "notes__spotlight").map((d) => d.id)).toEqual(["s"]);
    });

    it("maps underline to upstream's underline type and everything else to highlight", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(
        nav as any,
        "notes",
        JSON.stringify([item("h", "highlight"), item("u", "underline"), item("s", "spotlight")])
      );

      expect(appliedTo(nav, "notes").map((d) => d.style.type)).toEqual(["highlight", "underline"]);
      expect(appliedTo(nav, "notes__spotlight")[0].style.type).toBe("highlight");
      expect(appliedTo(nav, "notes")[1].style.layout).toBeUndefined();
    });

    it("passes an empty list for subgroups the new list no longer uses (replacement)", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "notes", JSON.stringify([item("s", "spotlight")]));
      nav.applyDecorations.mockClear();
      controller.applyDecorations(nav as any, "notes", JSON.stringify([item("h", "highlight")]));

      expect(appliedTo(nav, "notes").map((d) => d.id)).toEqual(["h"]);
      expect(nav.applyDecorations).toHaveBeenCalledWith([], "notes__spotlight");
    });

    it("clears every subgroup on an empty list", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "notes", "[]");

      expect(nav.applyDecorations.mock.calls.map(([list, g]) => [list, g])).toEqual([
        [[], "notes"],
        [[], "notes__spotlight"],
      ]);
    });

    it("activates spotlight only while the spotlight subgroup is non-empty", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "tts_range", JSON.stringify([item("s", "spotlight")]));
      controller.applyDecorations(nav as any, "tts_range", "[]");

      expect(mockSetSpotlightGroupOnIframes.mock.calls.map(([, g, active]) => [g, active])).toEqual([
        ["tts_range__spotlight", true],
        ["tts_range__spotlight", false],
      ]);
    });
  });

  describe("decoration taps", () => {
    it("registers observers for the group and its subgroups only when tappable", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "tts_utterance", JSON.stringify([item("a", "highlight")]));
      expect(nav.registerDecorationObserver).not.toHaveBeenCalled();

      controller.applyDecorations(nav as any, "notes", "[]", { tappable: true });
      expect(nav.registerDecorationObserver.mock.calls.map(([g]) => g)).toEqual([
        "notes",
        "notes__spotlight",
      ]);
    });

    it("registers once per group per navigator", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "notes", "[]", { tappable: true });
      controller.applyDecorations(nav as any, "notes", "[]", { tappable: true });
      expect(nav.registerDecorationObserver).toHaveBeenCalledTimes(2);

      // A new navigator (reopen) starts without observers.
      const nextNav = makeNav();
      controller.applyDecorations(nextNav as any, "notes", "[]", { tappable: true });
      expect(nextNav.registerDecorationObserver).toHaveBeenCalledTimes(2);
    });

    it("registers again after reset", () => {
      const { controller, nav } = setup();

      controller.applyDecorations(nav as any, "notes", "[]", { tappable: true });
      controller.reset();
      controller.applyDecorations(nav as any, "notes", "[]", { tappable: true });

      expect(nav.registerDecorationObserver).toHaveBeenCalledTimes(4);
    });

    it("emits a tap with the parent group, not the subgroup", () => {
      const { bridge, controller, nav } = setup();
      controller.applyDecorations(nav as any, "notes", JSON.stringify([item("s", "spotlight")]), {
        tappable: true,
      });
      const spotlightObserver = nav.registerDecorationObserver.mock.calls.find(
        ([g]) => g === "notes__spotlight"
      )![1];
      const decoration = appliedTo(nav, "notes__spotlight")[0];

      const handled = spotlightObserver.onDecorationActivated({
        decoration,
        group: "notes__spotlight",
        rect: { top: 0, left: 0, width: 1, height: 1 },
        point: { x: 0, y: 0 },
      });

      expect(handled).toBe(true);
      expect(bridge.emitDecorationInteraction).toHaveBeenCalledWith({
        decorationId: "s",
        group: "notes",
        type: "tap",
        locator: locator.serialize(),
      });
    });
  });
});
