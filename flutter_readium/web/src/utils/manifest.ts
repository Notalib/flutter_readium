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
 * Adds an HTML5 DOCTYPE to HTML-parsed chapters that lack one. Without it the frame renders in
 * quirks mode, where Safari's null `scrollingElement` stops Readium's pagination.
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
