import { Link, Manifest, Fetcher, HttpFetcher } from "@readium/shared";

export async function fetchManifest(publicationURL: string) {
  const manifestLink = new Link({ href: "manifest.json" });
  const fetcher: Fetcher = withHtmlDoctype(new HttpFetcher(undefined, publicationURL));
  const resource = fetcher.get(manifestLink);
  const resourceLink = await resource.link();
  const selfLink = resourceLink.toURL(publicationURL)!;
  const manifest = await resource.readAsJSON().then((response: unknown) => {
    const parsed = Manifest.deserialize(response as string)!;
    parsed.setSelfLink(selfLink);
    return parsed;
  });
  return { manifest, fetcher, selfLink };
}

/**
 * Gives HTML-parsed documents without a DOCTYPE an HTML5 one, so their frames
 * render in standards mode.
 *
 * Some publications declare XHTML chapters as `text/html`, and the chapters
 * have no DOCTYPE. Readium parses and re-serialises each chapter with the
 * declared type, so the frame renders in quirks mode. There Safari returns a
 * null `document.scrollingElement` (Readium CSS sets `overflow: clip` on html
 * and body), and Readium's pagination, which scrolls that element, cannot turn
 * pages or move between comic panels.
 */
export function withHtmlDoctype(fetcher: Fetcher): Fetcher {
  return {
    links: () => fetcher.links(),
    close: () => fetcher.close(),
    get: (link: Link) => {
      const resource = fetcher.get(link);
      const readAsXML = resource.readAsXML.bind(resource);
      resource.readAsXML = async () => {
        const doc = await readAsXML();
        if (doc?.contentType === "text/html" && !doc.doctype) {
          doc.insertBefore(doc.implementation.createDocumentType("html", "", ""), doc.firstChild);
        }
        return doc;
      };
      return resource;
    },
  };
}
