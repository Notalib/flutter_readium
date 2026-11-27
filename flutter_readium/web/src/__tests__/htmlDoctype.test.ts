/** @jest-environment jsdom */
import { Fetcher, Link, Resource } from "@readium/shared";
import { withHtmlDoctype } from "../utils/manifest";

function fetcherServing(markup: string, type: DOMParserSupportedType): Fetcher {
  const resource = {
    readAsXML: async () => new DOMParser().parseFromString(markup, type),
  } as unknown as Resource;
  return { links: () => [], close: () => {}, get: () => resource };
}

async function serialise(fetcher: Fetcher): Promise<string> {
  const doc = await withHtmlDoctype(fetcher).get(new Link({ href: "ch1.xhtml" })).readAsXML();
  return new XMLSerializer().serializeToString(doc!);
}

describe("withHtmlDoctype", () => {
  it("adds an HTML5 DOCTYPE to an HTML-parsed chapter that has none", async () => {
    const markup = "<html><head></head><body><p>x</p></body></html>";

    expect(await serialise(fetcherServing(markup, "text/html"))).toMatch(/^<!DOCTYPE html>/);
  });

  it("keeps an existing DOCTYPE", async () => {
    const markup = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" ""><html><body></body></html>';

    const out = await serialise(fetcherServing(markup, "text/html"));

    expect(out.match(/<!DOCTYPE/g)).toHaveLength(1);
    expect(out).toContain("XHTML 1.1");
  });

  it("leaves XHTML-parsed chapters alone", async () => {
    const markup = '<html xmlns="http://www.w3.org/1999/xhtml"><body></body></html>';

    expect(await serialise(fetcherServing(markup, "application/xhtml+xml"))).not.toContain("DOCTYPE");
  });
});
