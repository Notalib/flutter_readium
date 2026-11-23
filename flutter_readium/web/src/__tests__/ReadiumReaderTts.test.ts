/**
 * ReadiumReader.ttsEnable prepares TTS at the reader's position without
 * starting it, like iOS and Android: callers start reading with play().
 */
import { Locator, LocatorLocations } from "@readium/shared";
import { FlutterTTSNavigator } from "../navigators/FlutterTTSNavigator";
import { __testing__ } from "../ReadiumReader";

jest.mock("../navigators/FlutterTTSNavigator");

const { ReadiumReader } = __testing__;
const MockTTSNavigator = FlutterTTSNavigator as jest.MockedClass<typeof FlutterTTSNavigator>;

const readerLocator = new Locator({
  href: "chap2.html",
  type: "application/xhtml+xml",
  locations: new LocatorLocations({ progression: 0.5 }),
});

/** A content frame whose second paragraph is the first one on screen. */
function contentFrame(): Window {
  const p = (left: number): any => ({
    tagName: "P",
    firstElementChild: null,
    getBoundingClientRect: () => ({ left, right: left + 80, top: 0, bottom: 50, width: 80, height: 50 }),
  });
  const body: any = { tagName: "BODY" };
  const [p1, p2] = [p(-100), p(10)];
  Object.assign(p1, { parentElement: body, previousElementSibling: null, nextElementSibling: p2 });
  Object.assign(p2, { parentElement: body, previousElementSibling: p1, nextElementSibling: null });
  body.firstElementChild = p1;
  return { innerWidth: 100, innerHeight: 100, document: { body } } as unknown as Window;
}

function makeReader(): any {
  (globalThis as any).window = { updateReaderStatus: jest.fn() };
  (globalThis as any).document = { getElementById: () => null };
  const reader: any = new ReadiumReader();
  reader._publication = { manifest: {} };
  reader._nav = { currentLocator: readerLocator, _cframes: [{ window: contentFrame() }] };
  return reader;
}

/** The initial locator ttsEnable gave the engine. */
function initialLocatorOf(call: number): Locator | undefined {
  return MockTTSNavigator.mock.calls[call][7];
}

beforeEach(() => {
  MockTTSNavigator.mockClear();
});

afterEach(() => {
  delete (globalThis as any).window;
  delete (globalThis as any).document;
});

describe("ttsEnable", () => {
  it("does not start reading", async () => {
    const reader = makeReader();

    await reader.ttsEnable("{}");

    expect(MockTTSNavigator).toHaveBeenCalledTimes(1);
    expect(MockTTSNavigator.mock.instances[0].play).not.toHaveBeenCalled();
  });

  it("starts at the first element visible in the reader", async () => {
    const reader = makeReader();

    await reader.ttsEnable("{}");

    const start = initialLocatorOf(0);
    expect(start?.href).toBe("chap2.html");
    expect(start?.locations.otherLocations?.get("cssSelector")).toBe("body > :nth-child(2)");
  });

  it("starts at the caller's locator when given one", async () => {
    const reader = makeReader();

    await reader.ttsEnable("{}", JSON.stringify({ href: "chap7.html", type: "application/xhtml+xml" }));

    expect(initialLocatorOf(0)?.href).toBe("chap7.html");
  });

  it("lets play() without a locator resume the engine", async () => {
    const reader = makeReader();
    await reader.ttsEnable("{}");

    reader.play();

    expect(MockTTSNavigator.mock.instances[0].play).toHaveBeenCalledWith(undefined);
  });
});
