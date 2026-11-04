/**
 * A position-less initial locator (the shape Dart sends for `initialLocator`) is given the
 * chapter's `position` so the ts-toolkit navigator can find its frame. It must keep the
 * in-chapter location (progression, fragments, text) the caller supplied.
 */
import { Link, Links, Locator, LocatorLocations, LocatorText } from "@readium/shared";

let capturedInitial: Locator | undefined;

jest.mock("@readium/navigator", () => ({
  EpubNavigator: class {
    constructor(_c: unknown, _pub: unknown, _l: unknown, _positions: unknown, initial: Locator | undefined) {
      capturedInitial = initial;
    }
    async load() {}
  },
  WebPubNavigator: class {},
  FrameManager: class {},
  FXLFrameManager: class {},
}));

import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";

const chapter = (position: number) =>
  new Locator({
    href: "chap.xhtml",
    type: "application/xhtml+xml",
    locations: new LocatorLocations({ position, progression: 0 }),
  });

const publication = {
  positionsFromManifest: async () => [chapter(15), chapter(16)],
  manifest: { readingOrder: new Links([new Link({ href: "chap.xhtml" })]), toc: undefined },
} as any;

async function open(initial: Locator): Promise<Locator> {
  const container = {} as HTMLElement;
  await FlutterEpubNavigator.create(container, publication, initial, "{}", () => {});
  return capturedInitial!;
}

describe("FlutterEpubNavigator initial locator", () => {
  beforeEach(() => {
    capturedInitial = undefined;
    (globalThis as any).window = { addEventListener: () => {} };
  });
  afterEach(() => {
    delete (globalThis as any).window;
  });

  it("keeps progression, fragments and text when adding the chapter position", async () => {
    const resolved = await open(
      new Locator({
        href: "chap.xhtml",
        type: "application/xhtml+xml",
        text: new LocatorText({ highlight: "hello" }),
        locations: new LocatorLocations({ fragments: ["p42"], progression: 0.68, totalProgression: 0.5 }),
      })
    );

    expect(resolved.locations.position).toBe(15);
    expect(resolved.locations.fragments).toEqual(["p42"]);
    expect(resolved.locations.progression).toBe(0.68);
    expect(resolved.locations.totalProgression).toBe(0.5);
    expect(resolved.text?.highlight).toBe("hello");
  });
});
