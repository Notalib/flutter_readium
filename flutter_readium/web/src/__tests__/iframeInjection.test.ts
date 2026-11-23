/** @jest-environment jsdom */
import {
  injectFlutterReadiumHelperScripts,
  setHelperAssetUrls,
  setMarginDecorationSpaceInWindow,
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

describe("setMarginDecorationSpaceInWindow", () => {
  // The helper CSS rule matches this attribute; a root style property would be stripped by ts-toolkit.
  it("toggles the data attribute the helper CSS matches", () => {
    const frameDocument = document.implementation.createHTMLDocument();
    const wnd = { document: frameDocument } as unknown as Window;
    const attr = "data-flutter-readium-margin-decoration-space";

    setMarginDecorationSpaceInWindow(wnd, true);
    expect(frameDocument.documentElement.hasAttribute(attr)).toBe(true);

    setMarginDecorationSpaceInWindow(wnd, false);
    expect(frameDocument.documentElement.hasAttribute(attr)).toBe(false);
  });
});
