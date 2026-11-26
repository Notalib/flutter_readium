/** @jest-environment jsdom */
import {
  injectFlutterReadiumHelperScripts,
  scrollingElementGuardRule,
  setHelperAssetUrls,
} from "../utils/iframeInjection";

describe("injectFlutterReadiumHelperScripts", () => {
  it("fetches the helper URLs set from Dart, so content-hashed names resolve", async () => {
    const fetchMock = jest.fn(async (url: string) => ({ ok: true, text: async () => `/* ${url} */` }));
    global.fetch = fetchMock as unknown as typeof fetch;
    setHelperAssetUrls("assets/tools.0123abcd.js", "assets/tools.4567cdef.css");
    const frameDocument = document.implementation.createHTMLDocument();

    await injectFlutterReadiumHelperScripts({ document: frameDocument } as unknown as Window, []);

    expect(fetchMock.mock.calls.map(([url]) => url))
      .toEqual(["assets/tools.0123abcd.js", "assets/tools.4567cdef.css"]);
    expect(frameDocument.head.textContent).toContain("/* assets/tools.4567cdef.css */");
  });
});

describe("scrollingElementGuardRule", () => {
  // jsdom has no scrollingElement, so each test supplies the "native" getter.
  const nativeDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, "scrollingElement");

  async function runGuard(nativeValue: () => Element | null): Promise<void> {
    Object.defineProperty(Document.prototype, "scrollingElement", { configurable: true, get: nativeValue });
    const injectable = scrollingElementGuardRule().prepend![0];
    // jsdom's Blob has no text().
    const source = await new Promise<string>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result as string);
      reader.readAsText((injectable as { blob: Blob }).blob);
    });
    new Function(source)();
  }

  afterEach(() => {
    delete (document as { scrollingElement?: unknown }).scrollingElement;
    if (nativeDescriptor) {
      Object.defineProperty(Document.prototype, "scrollingElement", nativeDescriptor);
    } else {
      delete (Document.prototype as { scrollingElement?: unknown }).scrollingElement;
    }
  });

  it("falls back to <body> when the browser returns null (Safari, quirks mode)", async () => {
    await runGuard(() => null);
    expect(document.scrollingElement).toBe(document.body);
  });

  it("keeps the browser's value when it has one", async () => {
    await runGuard(() => document.documentElement);
    expect(document.scrollingElement).toBe(document.documentElement);
  });
});
