/** @jest-environment jsdom */
import { injectFlutterReadiumHelperScripts, setHelperAssetUrls } from "../utils/iframeInjection";

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
