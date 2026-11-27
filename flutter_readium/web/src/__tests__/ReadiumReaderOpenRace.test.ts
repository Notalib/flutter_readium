/**
 * A reader view can mount again (or the publication close) while an earlier
 * openPublication is still building its visual navigator. That navigator renders
 * into a container that is gone, so it must never become the reader's navigator.
 */
import { ReadiumPublication } from "../utils/ReadiumExtensions";

jest.mock("../navigators/FlutterEpubNavigator", () => ({
  ...jest.requireActual("../navigators/FlutterEpubNavigator"),
  FlutterEpubNavigator: { create: jest.fn() },
}));

import { FlutterEpubNavigator } from "../navigators/FlutterEpubNavigator";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;

function epubPublication(): ReadiumPublication {
  return {
    baseURL: "https://example.test/book/",
    conformsToAudiobook: false,
    conformsToEpub: true,
    conformsToDivina: false,
    metadata: { identifier: "urn:test:book" },
    readingOrder: { items: [] },
    resources: { items: [] },
    manifest: { links: undefined, toc: undefined },
  } as unknown as ReadiumPublication;
}

function fakeNav() {
  return { destroy: jest.fn(() => Promise.resolve()) };
}

/** Makes each FlutterEpubNavigator.create wait until the test finishes it. */
function deferredCreates() {
  const finishers: Array<() => void> = [];
  (FlutterEpubNavigator.create as jest.Mock).mockImplementation(
    (_c, _p, _i, _prefs, setNav, setPositions) =>
      new Promise<void>((resolve) => {
        const nav = fakeNav();
        finishers.push(() => {
          setNav(nav);
          setPositions([{ href: "stale" }]);
          resolve();
        });
        (finishers[finishers.length - 1] as any).nav = nav;
      })
  );
  return finishers as Array<(() => void) & { nav: ReturnType<typeof fakeNav> }>;
}

const open = (reader: any) =>
  reader.openPublication("https://example.test/book/manifest.json", "urn:test:book", undefined, "{}", "[]");

let savedWindow: any;
let savedDocument: any;

beforeEach(() => {
  savedWindow = (globalThis as any).window;
  savedDocument = (globalThis as any).document;
  (globalThis as any).window = { updateReaderStatus: jest.fn() };
  (globalThis as any).document = {
    getElementById: () => null,
    body: { querySelector: () => ({ innerHTML: "" }) },
  };
});

afterEach(() => {
  if (savedWindow === undefined) delete (globalThis as any).window;
  else (globalThis as any).window = savedWindow;
  if (savedDocument === undefined) delete (globalThis as any).document;
  else (globalThis as any).document = savedDocument;
  jest.clearAllMocks();
});

describe("overlapping openPublication calls", () => {
  it("keeps the latest view's navigator when an earlier create finishes last", async () => {
    const reader = new ReadiumReader();
    (reader as any)._publication = epubPublication();
    const creates = deferredCreates();

    const first = open(reader);
    const second = open(reader);
    creates[1]();
    await second;
    creates[0]();
    await first;

    expect((reader as any)._nav).toBe(creates[1].nav);
    expect(creates[0].nav.destroy).toHaveBeenCalledTimes(1);
    expect(creates[1].nav.destroy).not.toHaveBeenCalled();
  });

  it("does not install a navigator whose publication closed while it was created", async () => {
    const reader = new ReadiumReader();
    (reader as any)._publication = epubPublication();
    const creates = deferredCreates();

    const opening = open(reader);
    reader.closePublication();
    creates[0]();
    await opening;

    expect((reader as any)._nav).toBeUndefined();
    expect((reader as any)._positions).toEqual([]);
    expect(creates[0].nav.destroy).toHaveBeenCalledTimes(1);
  });

  it("does not close the newer book when a superseded open fails", async () => {
    const reader = new ReadiumReader();
    const publication = epubPublication();
    (reader as any)._publication = publication;
    let failFirst: ((e: Error) => void) | undefined;
    const current = fakeNav();
    (FlutterEpubNavigator.create as jest.Mock)
      .mockImplementationOnce(() => new Promise<void>((_resolve, reject) => { failFirst = reject; }))
      .mockImplementationOnce(async (_c, _p, _i, _prefs, setNav) => setNav(current));

    const first = open(reader);
    await open(reader);
    failFirst!(new Error("container is gone"));
    await expect(first).resolves.toBeUndefined();

    expect((reader as any)._nav).toBe(current);
    expect((reader as any)._publication).toBe(publication);
    expect(current.destroy).not.toHaveBeenCalled();
  });
});
