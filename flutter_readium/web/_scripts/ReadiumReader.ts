import './style.css';

import { EpubNavigator, EpubNavigatorConfiguration } from '@readium/navigator';
import { Locator, Publication, Resource } from '@readium/shared';
import { Link } from '@readium/shared';

// Design
import '@material/web/all';

// Helpers
import { fetchManifest, initializeNavigatorAndPeripherals } from './helpers';
import {
  defaults,
  initializePreferencesFromString,
  setPreferencesFromString,
} from './preferences';

class _ReadiumReader {
  public constructor() {
    console.log('R2Navigator initialized');
  }

  private _publication: Publication | undefined;
  private _nav: EpubNavigator | undefined;

  public get isNavigatorReady(): boolean {
    return !!this._nav;
  }

  private static _publications: Map<string, Publication> = new Map<
    string,
    Publication
  >();

  public async getPublication(publicationURL: string) {
    try {
      const { manifest, fetcher } = await fetchManifest(publicationURL);
      this._publication = new Publication({ manifest, fetcher });

      let pubId = this._publication.metadata.identifier ?? 'unidentified';
      _ReadiumReader._publications.set(pubId, this._publication);

      return JSON.stringify(this._publication);
    } catch (error) {
      throw new Error('Error getting publication: ' + error);
    }
  }

  public goRight() {
    this._nav?.goRight(true, () => {});
  }

  public goLeft() {
    this._nav?.goLeft(true, () => {});
  }

  public async goTo(href: string): Promise<void> {
    let link = this._nav?.publication.linkWithHref(href);
    if (!link) {
      let error = new Error('Link not found ' + href);
      throw error;
    }
    this._nav?.goLink(link, true, (ok) => {
      if (!ok) {
        let error = new Error('Failed to navigate to link ' + href);
        throw error;
      }
    });
  }

  public async openPublication(
    publicationURL: string,
    pubId: string,
    isAudiobook: boolean = false,
    hasText: boolean = false,
    initialPositionJson: string | undefined,
    preferencesJson: string | undefined
  ) {
    const container: HTMLElement | null =
      document.body.querySelector('#container');

    if (!container) {
      console.error('Container element not found');
      throw new Error('Container element not found');
    }

    let initialPosition: Locator | undefined;

    if (initialPositionJson) {
      initialPosition = Locator.deserialize(JSON.parse(initialPositionJson));
    }

    let preferencesJsonString =
      !preferencesJson || preferencesJson === 'null' ? '{}' : preferencesJson;

    let preferences = initializePreferencesFromString(preferencesJsonString);

    const configuration: EpubNavigatorConfiguration = {
      preferences,
      defaults,
    };

    try {
      this._publication = _ReadiumReader._publications.get(pubId);
      if (!this._publication) {
        const { manifest, fetcher } = await fetchManifest(publicationURL);
        this._publication = new Publication({ manifest, fetcher });
        _ReadiumReader._publications.set(pubId, this._publication);
      }

      if (isAudiobook) {
        // Initialize WebAudioEngine for audiobooks
        // TODO: wip

        // If the audiobook has text, initialize the navigator for text display
        if (hasText) {
          await initializeNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            configuration,
            (nav) => {
              this._nav = nav;
            }
          );
        }
      } else {
        // Initialize EpubNavigator for ebooks
        await initializeNavigatorAndPeripherals(
          container,
          this._publication,
          initialPosition,
          configuration,
          (nav) => {
            this._nav = nav;
          }
        );
      }
    } catch (error) {
      this.closePublication();
      throw new Error('Error opening publication: ' + error);
    }
  }

  public setEPUBPreferences(newPreferencesString: string) {
    if (!this._nav) {
      throw new Error('Navigator is not initialized');
    }
    setPreferencesFromString(newPreferencesString, this._nav);
  }

  public closePublication() {
    this._publication = undefined;
    this._nav?.destroy(); // Clean up the navigator instance
    const container = document.getElementById('container');
    if (container) {
      container.innerHTML = ''; // Clear the container
    }
    delete (window as any)._updateLocator;
  }

  public async getResource(linkString: String, asBytes: boolean = false) {
    // Step one - linkString to json object
    let linkJson = JSON.parse(linkString.toString());
    // Step two - json to Link object
    let link: Link | undefined = Link.deserialize(linkJson);
    if (!link) {
      console.error('Invalid link string');
    }
    // Step three - fetch the resource link
    let resourceLink: Resource | undefined = this._publication?.get(link!);

    if (!resourceLink) {
      console.error('Resource not found', link);
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
