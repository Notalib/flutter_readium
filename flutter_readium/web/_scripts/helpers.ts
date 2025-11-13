import {
  EpubNavigator,
  TextAlignment,
  WebPubNavigator,
} from "@readium/navigator";
import {
  BasicTextSelection,
  Width,
  Layout,
} from "@readium/navigator-html-injectables";
import {
  Manifest,
  Link,
  Fetcher,
  HttpFetcher,
  MediaType,
  Locator,
  LocatorText,
} from "@readium/shared";
import { ReadiumPublication } from "./extensions/ReadiumPublication";

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

export function mediaTypes(publication: ReadiumPublication) {
  let selfLinks = publication.manifest.linksWithRel("self");
  let mediaTypesString = selfLinks
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

export function highlightSelection(
  nav: EpubNavigator | WebPubNavigator,
  publication: ReadiumPublication,
  selection: BasicTextSelection
) {
  // TODO: Save decoration state to re-apply after reload
  // Should probably be handled by the Flutter side
  // TODO:  Make optional and configurable decoration style
  // For now, hardcode a simple highlight style that always happens on textSelection
  const currentLocator = nav.currentLocator;
  const locator = new Locator({
    href: currentLocator.href,
    type: currentLocator.type,
    locations: currentLocator.locations,
    text: {
      highlight: selection.text,
    } as LocatorText,
  });

  const decorationId = [selection.text, selection.x, selection.y].join("_");

  const decoration = {
    id: decorationId,
    locator,
    style: {
      tint: "#ff9fff55",
      layout: Layout.Bounds,
      width: Width.Wrap,
    },
  };

  const frameComms = nav._cframes[0]?.msg;
  if (frameComms) {
    frameComms.send("decorate", {
      group: "selection_" + publication.metadata.identifier,
      action: "add",
      decoration,
    });
  } else {
    throw new Error("Could not find frame comms to send decoration");
  }
}
