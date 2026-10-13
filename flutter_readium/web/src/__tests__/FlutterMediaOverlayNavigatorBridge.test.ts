/**
 * Media Overlay sessions only get stream error recovery when the bridge reaches
 * `FlutterAudioNavigator.create`. Guards that wiring for both parsers.
 */

import { Locator, LocatorLocations, Manifest } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { SyncNarrationItem } from "../mediaoverlay/syncNarration";

const ITEMS: SyncNarrationItem[] = [
  {
    audio: "audio/01.mp3",
    text: "chap.xhtml",
    position: 1,
    audioHref: "audio/01.mp3",
    audioStart: 0,
    audioEnd: 5,
    textHref: "chap.xhtml",
    textId: "p1",
    tocHref: "chap.xhtml#section",
    tocTitle: "Section",
  },
];

jest.mock("../mediaoverlay/syncNarration", () => ({
  ...jest.requireActual("../mediaoverlay/syncNarration"),
  parseSyncNarration: jest.fn(async () => ITEMS),
}));
jest.mock("../mediaoverlay/guidedNavigation", () => ({
  ...jest.requireActual("../mediaoverlay/guidedNavigation"),
  parseGuidedNavigation: jest.fn(async () => ITEMS),
}));

import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import {
  initializeGuidedNavigationNavigator,
  initializeMediaOverlayNavigator,
} from "../navigators/FlutterMediaOverlayNavigator";

function publication(): ReadiumPublication {
  const manifest = Manifest.deserialize({
    metadata: { title: "Test" },
    links: [{ rel: "self", href: "https://example.test/pub/manifest.json" }],
    readingOrder: [{ href: "chap.xhtml", type: "application/xhtml+xml" }],
  })!;
  return new ReadiumPublication({ manifest } as never);
}

afterEach(() => jest.restoreAllMocks());

it.each([
  ["sync narration", initializeMediaOverlayNavigator],
  ["guided navigation", initializeGuidedNavigationNavigator],
])("%s passes the bridge and a locator mapper to create()", async (_label, initialize) => {
  const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
  const bridge = { emitError: jest.fn() } as unknown as ReadiumBridge;

  await initialize(publication(), undefined, "{}", () => {}, undefined, bridge);

  expect(create).toHaveBeenCalledTimes(1);
  const args = create.mock.calls[0];
  expect(args[4]).toBeDefined(); // locatorMapper
  expect(args[7]).toBe(bridge);
});


it.each([
  ["sync narration", initializeMediaOverlayNavigator, ["t=3"]],
  ["guided navigation", initializeGuidedNavigationNavigator, ["t=0"]],
] as const)("%s factory applies its own initial-locator policy", async (_label, initialize, expected) => {
  const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
  const locator = new Locator({href: "chap.xhtml", type: "text/html", locations: new LocatorLocations({fragments: ["t=npt:0:00:03", "section"]})});
  await initialize(publication(), locator, "{}", () => {});
  expect(create.mock.calls[0][1]?.locations.fragments).toEqual(expected);
});

it("combined bridge locator retains assigned owner and cue selector", async () => {
  const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
  await initializeMediaOverlayNavigator(publication(), undefined, "{}", () => {});
  const mapper = create.mock.calls[0][4]!;
  const audio = new Locator({href: "https://example.test/pub/audio/01.mp3", type: "audio/mpeg", locations: new LocatorLocations({fragments: ["t=2"], progression: .4, totalProgression: .4})});
  const mapped = mapper({currentTime: 2} as never, audio).stateLocator.serialize();
  expect(mapped.locations).toMatchObject({cssSelector: "#p1", tocHref: "chap.xhtml#section", position: 2, progression: .4, totalProgression: .4});
});
