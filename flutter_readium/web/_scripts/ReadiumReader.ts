import "./style.css";

import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Locator, Profile, Publication, Resource } from "@readium/shared";
import { Link } from "@readium/shared";

// Helpers and extensions
import { fetchManifest, setPreferencesFromString } from "./helpers";
import { ReadiumReaderStatus } from "./enums";
import { ReadiumPublication } from "./extensions/ReadiumPublication";
import { initializeEpubNavigatorAndPeripherals } from "./Epub/epubNavigator";
import { initializeWebPubNavigatorAndPeripherals } from "./WebPub/webpubNavigator";

class _ReadiumReader {
  public constructor() {
    console.log("R2Navigator initialized");
  }

  private _publication: ReadiumPublication | undefined;
  private _nav: EpubNavigator | WebPubNavigator | undefined;

  public get isNavigatorReady(): boolean {
    return !!this._nav;
  }

  private static _publications: Map<string, ReadiumPublication> = new Map<
    string,
    ReadiumPublication
  >();

  public async getPublication(publicationURL: string) {
    try {
      const { manifest, fetcher } = await fetchManifest(publicationURL);
      this._publication = new ReadiumPublication({ manifest, fetcher });

      let pubId = this._publication.metadata.identifier ?? "unidentified";
      _ReadiumReader._publications.set(pubId, this._publication);

      return JSON.stringify(this._publication);
    } catch (error) {
      throw new Error("Error getting publication: " + error);
    }
  }

  public goRight() {
    this._nav?.goRight(true, () => {});
  }

  public goLeft() {
    this._nav?.goLeft(true, () => {});
  }

  public async goTo(href: string): Promise<void> {
    let link = this._nav?.publication.resources?.findWithHref(href);
    if (!link) {
      let publicationLinks = this._nav?.publication.resources;
      let linksString = publicationLinks?.items
        .map((link) => link.href)
        .join(", ");
      console.error(
        "Link not found " + href + ". Available links: " + linksString
      );
      let error = new Error("Link not found " + href);
      throw error;
    }
    this._nav?.goLink(link, true, (ok) => {
      if (!ok) {
        let error = new Error("Failed to navigate to link " + href);
        throw error;
      }
    });
  }

  public async openPublication(
    publicationURL: string,
    pubId: string,
    initialPositionJson: string | undefined,
    preferencesJson: string | undefined
  ) {
    (window as any).updateReaderStatus?.(ReadiumReaderStatus.loading);
    const container: HTMLElement | null =
      document.body.querySelector("#container");

    if (!container) {
      console.error("Container element not found");
      (window as any).updateReaderStatus?.("error");
      throw new Error("Container element not found");
    }

    let initialPosition: Locator | undefined;

    if (initialPositionJson) {
      initialPosition = Locator.deserialize(JSON.parse(initialPositionJson));
    }

    let preferencesJsonString =
      !preferencesJson || preferencesJson === "null" ? "{}" : preferencesJson;

    try {
      // TODO: match native
      this._publication = _ReadiumReader._publications.get(pubId);
      if (!this._publication) {
        const { manifest, fetcher } = await fetchManifest(publicationURL);
        this._publication = new ReadiumPublication({ manifest, fetcher });
        _ReadiumReader._publications.set(pubId, this._publication);
      }
      let conformsToArray = this._publication.manifest.metadata.conformsTo;

      if (this._publication.conformsToAudiobook) {
        // Initialize WebAudioEngine for audiobooks
        // TODO: wip
      } else {
        // Initialize EpubNavigator for ebooks
        if (this._publication.conformsToEpub) {
          await initializeEpubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              (window as any).updateReaderStatus?.(ReadiumReaderStatus.ready);
            }
          );
        } else {
          await initializeWebPubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              (window as any).updateReaderStatus?.(ReadiumReaderStatus.ready);
            }
          );
        }
      }
    } catch (error) {
      this.closePublication(error);
      throw new Error("Error opening publication: " + error);
    }
  }

  public setEPUBPreferences(newPreferencesString: string) {
    if (!this._nav) {
      throw new Error("Navigator is not initialized");
    }
    setPreferencesFromString(newPreferencesString, this._nav);
  }

  public closePublication(error?: any) {
    this._publication = undefined;
    this._nav?.destroy(); // Clean up the navigator instance
    const container = document.getElementById("container");
    if (container) {
      container.innerHTML = ""; // Clear the container
    }
    if (error) {
      (window as any).updateReaderStatus?.(ReadiumReaderStatus.error);
    } else {
      (window as any).updateReaderStatus?.(ReadiumReaderStatus.closed);
    }

    delete (window as any).updateTextLocator;
    delete (window as any).updateReaderStatus;
  }

  public async getResource(linkString: String, asBytes: boolean = false) {
    // Step one - linkString to json object
    let linkJson = JSON.parse(linkString.toString());
    // Step two - json to Link object
    let link: Link | undefined = Link.deserialize(linkJson);
    if (!link) {
      console.error("Invalid link string");
    }
    // Step three - fetch the resource link
    let resourceLink: Resource | undefined = this._publication?.get(link!);

    if (!resourceLink) {
      console.error("Resource not found", link);
    }

    // Step four - get resource as string
    let resourceString: string | undefined;
    if (asBytes) {
      let resourceBytes = await resourceLink?.read();
      resourceString = JSON.stringify(Array.from(resourceBytes!));
    } else {
      resourceString = await resourceLink?.readAsString();
    }

    return resourceString;
  }
}

declare global {
  namespace globalThis {
    var ReadiumReader: typeof _ReadiumReader;
  }
}

globalThis.ReadiumReader = _ReadiumReader;
