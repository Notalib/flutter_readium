/**
 * Media Overlay sessions only get stream error recovery when the bridge reaches
 * `FlutterAudioNavigator.create`. Guards that wiring for both parsers.
 */

import { Locator, LocatorLocations, Manifest } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { UncuedTocTargets } from "../mediaoverlay/uncuedTocTargets";
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


it.each([
  ["Sync", initializeMediaOverlayNavigator, "heading", "two.xhtml#section"],
  ["Guided", initializeGuidedNavigationNavigator, "boundary", "one.xhtml#section"],
] as const)("%s event mapper and initial cue respect their boundary policy", async (_label, initialize, id, owner) => {
  const original = [...ITEMS];
  const cue = (textHref: string, textId: string, start: number, end: number, tocHref: string): SyncNarrationItem => ({
    audio: `audio/01.mp3#t=${start},${end}`, audioHref: "audio/01.mp3", audioStart: start, audioEnd: end,
    text: `${textHref}#${textId}`, textHref, textId, position: 0, tocHref,
  });
  ITEMS.splice(0, ITEMS.length,
    cue("one.xhtml", "boundary", 14, 16, "one.xhtml#section"),
    cue("two.xhtml", "heading", 16, 18, "two.xhtml#section"));
  try {
    const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
    const onText = jest.fn();
    const initial = new Locator({href: "two.xhtml", type: "text/html", locations: new LocatorLocations({fragments: ["heading"]})});
    await initialize(publication(), initial, "{}", () => {}, onText);
    expect(onText.mock.calls[0][0].locations.otherLocations.get("cssSelector")).toBe(`#${id}`);
    expect(onText.mock.calls[0][0].locations.otherLocations.get("tocHref")).toBe(owner);
    const mapper = create.mock.calls[0][4]!;
    const audio = new Locator({href: "https://example.test/pub/audio/01.mp3", type: "audio/mpeg", locations: new LocatorLocations({fragments: ["t=16"]})});
    const mapped = mapper({currentTime: 16} as never, audio).stateLocator;
    expect(mapped.locations.otherLocations?.get("cssSelector")).toBe(`#${id}`);
    expect(mapped.locations.otherLocations?.get("tocHref")).toBe(owner);
    expect(mapped.href).toBe(_label === "Sync" ? "two.xhtml" : "one.xhtml");
  } finally {
    ITEMS.splice(0, ITEMS.length, ...original);
  }
});


it("anchors an uncued initial locator before creating the audio navigator", async () => {
  const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
  const anchored = new Locator({href: "chap.xhtml", type: "application/xhtml+xml",
    locations: new LocatorLocations({fragments: ["p1"]})});
  const anchor = jest.spyOn(UncuedTocTargets.prototype, "anchor").mockResolvedValue(anchored);
  const initial = new Locator({href: "chap.xhtml", type: "application/xhtml+xml",
    locations: new LocatorLocations({fragments: ["empty-heading"]})});
  await initializeMediaOverlayNavigator(publication(), initial, "{}", () => {});
  expect(anchor).toHaveBeenCalledWith(initial);
  expect(create.mock.calls[0][1]?.locations.fragments).toEqual(["t=0"]);
});

it("emits the first cue without waiting for its owner and enriches subsequent events", async () => {
  const original = [...ITEMS];
  ITEMS.splice(0, ITEMS.length, {...ITEMS[0], tocHref: undefined, tocTitle: undefined});
  let items: SyncNarrationItem[] = [];
  let release!: () => void;
  const pending = new Promise<void>((done) => {release = done;});
  jest.spyOn(UncuedTocTargets.prototype, "fillOwners").mockImplementation(async () => {
    await pending;
    items[0].tocHref = "chap.xhtml#section";
  });
  const create = jest.spyOn(FlutterAudioNavigator, "create").mockImplementation(async (...args) => {
    args[3]({} as never);
  });
  try {
    await initializeMediaOverlayNavigator(publication(), undefined, "{}", (_nav, installed) => {items = installed;});
    const mapper = create.mock.calls[0][4]!;
    const audio = new Locator({href: items[0].audioHref, type: "audio/mpeg",
      locations: new LocatorLocations({fragments: ["t=2"]})});
    const before = mapper({currentTime: 2} as never, audio);
    expect(before.stateLocator.locations.otherLocations?.get("tocHref")).toBeUndefined();
    expect(before.textLocator?.locations.otherLocations?.get("cssSelector")).toBe("#p1");
    release();
    await pending;
    const after = mapper({currentTime: 2} as never, audio);
    expect(after.stateLocator.locations.otherLocations?.get("tocHref")).toBe("chap.xhtml#section");
    expect(after.textLocator?.locations.otherLocations?.get("tocHref")).toBe("chap.xhtml#section");
  } finally {
    release();
    ITEMS.splice(0, ITEMS.length, ...original);
  }
});

// Guided Navigation cues get the same XHTML owner correction as Sync Narration, but keep their own seek policy.
// They must not start using the Sync Narration owner and anchor seeks.
it("guided source with both interfaces prepares owners without enabling Sync Narration seeks", async () => {
  // Given: a publication with both interfaces, and guided cues that all carry heading `h` as their owner.
  // The XHTML puts `p2` in section `s2`, and the initial locator points at `s2`.
  const original = [...ITEMS];
  const originalParser = (globalThis as any).DOMParser;
  const cue = (id: string, start: number): SyncNarrationItem => ({
    audio: `audio/01.mp3#t=${start},${start + 5}`, text: `chap.xhtml#${id}`, position: 0,
    audioHref: "audio/01.mp3", audioStart: start, audioEnd: start + 5,
    textHref: "chap.xhtml", textId: id, tocHref: "chap.xhtml#h", tocTitle: "Detail",
  });
  ITEMS.splice(0, ITEMS.length, cue("h", 0), cue("p1", 5), cue("p2", 10));
  const el = (id: string, ...children: any[]) => ({id, children});
  (globalThis as any).DOMParser = class {
    parseFromString() {
      return {getElementsByTagName: () => [], documentElement: el("", el("s1", el("h"), el("p1")), el("s2", el("p2")))};
    }
  };
  try {
    const manifest = Manifest.deserialize({
      metadata: {title: "Boundary test"},
      links: [{rel: "self", href: "https://example.test/pub/manifest.json"},
        {href: "guided.json", type: "application/guided-navigation+json"}],
      readingOrder: [{href: "chap.xhtml", type: "application/xhtml+xml",
        alternate: [{href: "sync.json", type: "application/vnd.syncnarr+json"}]}],
      toc: [{href: "chap.xhtml#s1", children: [{href: "chap.xhtml#h"}]}, {href: "chap.xhtml#s2", title: "Second"}],
    })!;
    const pub = new ReadiumPublication({manifest} as never);
    jest.spyOn(pub, "get").mockReturnValue({readAsString: async () => "<html/>"} as never);
    const create = jest.spyOn(FlutterAudioNavigator, "create").mockResolvedValue();
    const setNav = jest.fn();
    const initial = new Locator({href: "chap.xhtml", type: "application/xhtml+xml", locations: new LocatorLocations({fragments: ["s2"]})});
    // When: the guided navigator is initialized.
    await initializeGuidedNavigationNavigator(pub, initial, "{}", setNav);
    const mapper = create.mock.calls[0][4]!;
    const audio = new Locator({href: "https://example.test/pub/audio/01.mp3", type: "audio/mpeg", locations: new LocatorLocations({fragments: ["t=12"]})});
    // Then: playback inside `p2` reports the corrected owner `s2`.
    expect(mapper({currentTime: 12} as never, audio).stateLocator.locations.otherLocations?.get("tocHref")).toBe("chap.xhtml#s2");
    // Then: the initial `s2` locator keeps the guided policy (start of the audio), not the first cue of `s2`.
    expect(create.mock.calls[0][1]?.locations.fragments).toEqual(["t=0"]);
    const install = create.mock.calls[0][3];
    // The guided path must not publish the Sync Narration anchor resolver to callers.
    install({} as never);
    expect(setNav.mock.calls[0][2]).toBeUndefined();
  } finally {
    ITEMS.splice(0, ITEMS.length, ...original);
    (globalThis as any).DOMParser = originalParser;
  }
});
