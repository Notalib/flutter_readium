import { Locator, LocatorLocations } from "@readium/shared";
import { DecorationController } from "../decorations/DecorationController";

const mockSendDecorate = jest.fn();
const mockNavIframeWindows = jest.fn((_nav: unknown): Window[] => []);
const mockRegisterPendingDecorationGroup = jest.fn(
  (_iframes: Window[], _group: string, _isUnderline: boolean, _tint: string): void => {}
);
const mockSetSpotlightGroupOnIframes = jest.fn(
  (_iframes: Window[], _group: string, _active: boolean): void => {}
);
const mockClearSpotlightState = jest.fn();

jest.mock("../decorations/decorationFrameUtils", () => ({
  UNDERLINE_GROUP_SUFFIX: "__underline",
  SPOTLIGHT_GROUP_SUFFIX: "__spotlight",
  sendDecorate: (
    nav: unknown,
    group: string,
    action: string,
    decoration: unknown
  ) => mockSendDecorate(nav, group, action, decoration),
  navIframeWindows: (nav: unknown) => mockNavIframeWindows(nav),
  registerPendingDecorationGroup: (
    iframes: Window[],
    group: string,
    isUnderline: boolean,
    tint: string
  ) => mockRegisterPendingDecorationGroup(iframes, group, isUnderline, tint),
  setSpotlightGroupOnIframes: (iframes: Window[], group: string, active: boolean) =>
    mockSetSpotlightGroupOnIframes(iframes, group, active),
  clearSpotlightState: () => mockClearSpotlightState(),
}));

describe("DecorationController", () => {
  beforeEach(() => {
    mockSendDecorate.mockClear();
    mockNavIframeWindows.mockClear();
    mockRegisterPendingDecorationGroup.mockClear();
    mockSetSpotlightGroupOnIframes.mockClear();
    mockClearSpotlightState.mockClear();
  });

  it("disables contrast enforcement for plugin-owned highlight tints", () => {
    const controller = new DecorationController();
    const nav = {} as any;
    const locator = new Locator({
      href: "chapter-1.xhtml",
      type: "application/xhtml+xml",
      locations: new LocatorLocations({ fragments: ["p1"] }),
    });

    controller.applyDecorations(
      nav,
      "tts_utterance",
      JSON.stringify([
        {
          id: "dec-1",
          locator: locator.serialize(),
          style: { style: "highlight", tint: "#ccfdff00" },
        },
      ])
    );

    expect(mockSendDecorate).toHaveBeenCalledWith(nav, "tts_utterance", "clear", undefined);
    expect(mockSendDecorate).toHaveBeenCalledWith(
      nav,
      "tts_utterance",
      "add",
      expect.objectContaining({
        id: "dec-1",
        style: expect.objectContaining({
          tint: "#fdff00cc",
          enforceContrast: false,
        }),
      })
    );
  });
});
