/**
 * Regression tests for remounting the reader view of the open publication.
 *
 * Apps rebuild the reader view (for example on a layout change), so the old view's frames
 * are gone by the time the new view mounts and opens the publication again. Tearing down
 * the old session must not fail on those frames, and a failed open must not forget the
 * publication, or every later mount is rejected.
 */
import { Link } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

jest.mock("../navigators/FlutterEpubNavigator", () => ({
  ...jest.requireActual("../navigators/FlutterEpubNavigator"),
  FlutterEpubNavigator: { create: jest.fn() },
}));

import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;
const create = FlutterEpubNavigator.create as jest.Mock;
const url = "https://example.test/book/manifest.json";

function epubPublication(): ReadiumPublication {
  return {
    baseURL: "https://example.test/book/",
    conformsToAudiobook: false,
    conformsToEpub: true,
    conformsToDivina: false,
    metadata: { identifier: "urn:test:book" },
    readingOrder: { items: [new Link({ href: "chapter1.xhtml" })] },
    resources: { items: [] },
    manifest: { links: undefined, toc: undefined, metadata: { languages: ["en"] } },
  } as unknown as ReadiumPublication;
}

/** A visual navigator with one content frame, which `removeFrame` takes away like a remount does. */
function fakeNav() {
  let frameWindow: Window | null = { document: {} } as unknown as Window;
  const frame = {
    // The toolkit's FrameManager throws like this once its iframe is gone.
    get window(): Window {
      if (!frameWindow) throw Error("Trying to use frame window when it doesn't exist");
      return frameWindow;
    },
  };
  return {
    _cframes: [frame],
    currentLocator: undefined,
    applyDecorations: jest.fn(),
    destroy: jest.fn(async () => {}),
    removeFrame: () => {
      frameWindow = null;
    },
  };
}

async function openReader() {
  const reader = new ReadiumReader();
  (reader as any)._pubManager = {
    fetch: jest.fn().mockResolvedValue({ publication: epubPublication(), manifestJson: "{}" }),
  };
  await reader.loadAsCurrentPublication(url);
  return reader;
}

const mount = (reader: InstanceType<typeof ReadiumReader>) =>
  reader.openPublication(url, "urn:test:book", undefined, "{}", "[]");

let savedWindow: any;
let savedDocument: any;
let savedSpeech: any;

beforeEach(() => {
  savedWindow = (globalThis as any).window;
  savedDocument = (globalThis as any).document;
  savedSpeech = (globalThis as any).speechSynthesis;
  (globalThis as any).window = { updateReaderStatus: jest.fn() };
  (globalThis as any).document = {
    getElementById: () => null,
    body: { querySelector: () => ({ innerHTML: "" }) },
  };
  (globalThis as any).speechSynthesis = {
    speaking: false,
    pending: false,
    paused: false,
    cancel: jest.fn(),
    getVoices: () => [],
  };
  create.mockReset();
});

afterEach(() => {
  for (const [key, saved] of [["window", savedWindow], ["document", savedDocument], ["speechSynthesis", savedSpeech]]) {
    if (saved === undefined) delete (globalThis as any)[key];
    else (globalThis as any)[key] = saved;
  }
});

describe("remounting the reader view", () => {
  it("reopens the publication after a remount while TTS is active", async () => {
    const reader = await openReader();
    const first = fakeNav();
    create.mockImplementation(async (_c, _p, _i, _prefs, setNav) => setNav(fakeNav()));
    create.mockImplementationOnce(async (_c, _p, _i, _prefs, setNav) => setNav(first));
    await mount(reader);
    await reader.ttsEnable("{}");

    first.removeFrame();

    await expect(mount(reader)).resolves.toBeUndefined();
    await expect(mount(reader)).resolves.toBeUndefined();
    expect(create).toHaveBeenCalledTimes(3);
  });

  it("keeps the publication when an open fails, so the next mount can retry", async () => {
    const reader = await openReader();
    create.mockRejectedValueOnce(new Error("navigator failed"));
    create.mockImplementation(async (_c, _p, _i, _prefs, setNav) => setNav(fakeNav()));

    await expect(mount(reader)).rejects.toThrow("navigator failed");

    await expect(mount(reader)).resolves.toBeUndefined();
  });
});
