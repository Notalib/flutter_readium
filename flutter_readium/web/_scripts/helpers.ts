import {
  EpubNavigator,
  TextAlignment,
  WebPubNavigator,
} from "@readium/navigator";
import {
  Publication,
  Manifest,
  Link,
  Fetcher,
  HttpFetcher,
  MediaType,
} from "@readium/shared";

export async function fetchManifest(publicationURL: string) {
  const manifestLink = new Link({ href: "manifest.json" });
  const fetcher: Fetcher = new HttpFetcher(undefined, publicationURL);
  const resource = fetcher.get(manifestLink);
  const resourceLink = await resource.link();
  const selfLink = resourceLink.toURL(publicationURL)!;
  const manifest = await resource.readAsJSON().then((response: unknown) => {
    const manifest = Manifest.deserialize(response as string)!;
    manifest.setSelfLink(selfLink);
    return manifest;
  });
  return { manifest, fetcher, selfLink };
}

export function mediaTypes(publication: Publication) {
  let mediaTypesLinks = publication.manifest.links.filterLinksHasType();
  let mediaTypesString = mediaTypesLinks
    .map((link) => link.type)
    .filter((type): type is string => typeof type === "string");

  let mediaTypes: MediaType[] = mediaTypesString.map((type) =>
    MediaType.parse({ mediaType: type })
  );

  return mediaTypes;
}

export function convertVerticalScroll(prefs: any) {
  if ("verticalScroll" in prefs) {
    prefs.scroll = prefs.verticalScroll;
    delete prefs.verticalScroll;
  }
}

export function textAlignFromJson(textAlignString: string): TextAlignment {
  switch (textAlignString) {
    case "left":
      return TextAlignment.left;
    case "right":
      return TextAlignment.right;
    case "start":
      return TextAlignment.start;
    case "justify":
      return TextAlignment.justify;
    default:
      return TextAlignment.left;
  }
}

export function normalizeTypes(obj: any): any {
  if (Array.isArray(obj)) {
    return obj.map(normalizeTypes);
  } else if (obj !== null && typeof obj === "object") {
    for (const key in obj) {
      if (!obj.hasOwnProperty(key)) continue;
      const value = obj[key];
      if (typeof value === "string") {
        if (value === "true") {
          obj[key] = true;
        } else if (value === "false") {
          obj[key] = false;
        } else if (/^-?\d+(\.\d+)?$/.test(value)) {
          // Only convert if the string is a pure number (int or float)
          obj[key] = value.includes(".")
            ? parseFloat(value)
            : parseInt(value, 10);
        }
      } else if (typeof value === "object" && value !== null) {
        obj[key] = normalizeTypes(value);
      } else if (value === "null" || value == null) {
        delete obj[key];
      }
    }
  }
  return obj;
}

export function setPreferencesFromString(
  newPreferencesString: string,
  nav: EpubNavigator | WebPubNavigator
) {
  let newPreferences = JSON.parse(newPreferencesString);

  convertVerticalScroll(newPreferences);

  if (newPreferences.textAlign != null) {
    newPreferences.textAlign = textAlignFromJson(newPreferences.textAlign);
  }
  if (newPreferences.pageMargins != null) {
    newPreferences.pageGutter = newPreferences.pageMargins;
    delete newPreferences.pageMargins;
  }

  newPreferences = normalizeTypes(newPreferences);

  // if (nav instanceof EpubNavigator) {
  nav.submitPreferences(newPreferences);
  // }
}
