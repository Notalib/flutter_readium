import './style.css';

import {
  BasicTextSelection,
  FrameClickEvent,
} from '@readium/navigator-html-injectables';
import {
  EpubNavigator,
  EpubNavigatorListeners,
  FrameManager,
  FXLFrameManager,
  EpubNavigatorConfiguration,
} from '@readium/navigator';
import {
  Locator,
  LocatorLocations,
  Manifest,
  Publication,
  Resource,
} from '@readium/shared';
import { Fetcher } from '@readium/shared';
import { HttpFetcher } from '@readium/shared';
import { Link } from '@readium/shared';

// Design
import '@material/web/all';
import Peripherals from './peripherals';
import {
  defaults,
  setPreferencesFromString,
  updatePreferences,
} from './preferences';

class _ReadiumReader {
  public constructor() {
    console.log('R2Navigator initialized');
  }

  private _publication: Publication | undefined;
  private _nav: EpubNavigator | undefined;

  private async fetchManifest(publicationURL: string) {
    const manifestLink = new Link({ href: 'manifest.json' });
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

  public async getPublication(publicationURL: string) {
    try {
      const { manifest, fetcher } = await this.fetchManifest(publicationURL);
      this._publication = new Publication({ manifest, fetcher });

      return JSON.stringify(this._publication);
    } catch (error) {
      throw new Error('Error getting publication: ' + error);
    }
  }

  private initializeNavigator(
    container: HTMLElement,
    publication: Publication,
    listeners: EpubNavigatorListeners,
    positions: any,
    initialPosition: Locator | undefined = undefined,
    configuration: EpubNavigatorConfiguration
  ) {
    const nav = new EpubNavigator(
      container,
      publication,
      listeners,
      positions,
      initialPosition,
      configuration
    );
    return nav;
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
      if (ok) {
        console.log('Navigated to', link.href, link.title, link.type);
      }
    });
  }

  private async initializeNavigatorAndPeripherals(
    container: HTMLElement,
    publication: Publication,
    initialPosition: Locator | undefined = undefined,
    configuration: EpubNavigatorConfiguration
  ) {
    let positions = await publication.positionsFromManifest();

    if (positions.length === 0) {
      // Use readingOrder if positionListLink is undefined
      positions = publication.manifest.readingOrder.items.map(
        (link: Link, index: number) => {
          return new Locator({
            href: link.href,
            type: link.type ?? 'text/html',
            title: link.title,
            locations: new LocatorLocations({
              position: index + 1,
            }),
          });
        }
      );
    }

    const p = new Peripherals({
      moveTo: (direction) => {
        if (direction === 'right') {
          nav.goRight(true, () => {});
        } else if (direction === 'left') {
          nav.goLeft(true, () => {});
        }
      },
      menu: (_show) => {
        // No UI that hides/shows at the moment
      },
      goProgression: (_shiftKey) => {
        nav.goForward(true, () => {});
      },
    });

    const listeners: EpubNavigatorListeners = {
      frameLoaded: function (_wnd: Window): void {
        nav._cframes.forEach(
          (frameManager: FrameManager | FXLFrameManager | undefined) => {
            if (frameManager) {
              p.observe(frameManager.window);
            }
          }
        );
        p.observe(window);
      },
      positionChanged: (_locator: Locator): void => {
        window.focus();

        if ((window as any).updateLocator) {
          (window as any).updateLocator(JSON.stringify(_locator));
        }
      },
      tap: function (_e: FrameClickEvent): boolean {
        return false;
      },
      click: function (_e: FrameClickEvent): boolean {
        return false;
      },
      zoom: function (_scale: number): void {},
      miscPointer: function (_amount: number): void {
        // fires when a tap or a click was made in the middle of the iframe e.g. show/hide UI
      },
      customEvent: function (_key: string, _data: unknown): void {},
      handleLocator: function (locator: Locator): boolean {
        const href = locator.href;
        if (
          href.startsWith('http://') ||
          href.startsWith('https://') ||
          href.startsWith('mailto:') ||
          href.startsWith('tel:')
        ) {
          if (confirm(`Open "${href}" ?`)) window.open(href, '_blank');
        } else {
          console.warn('Unhandled locator', locator);
        }
        return false;
      },
      textSelected: function (_selection: BasicTextSelection): void {},
    };

    const nav = this.initializeNavigator(
      container,
      publication,
      listeners,
      positions,
      initialPosition,
      configuration
    );

    try {
      await nav.load();
    } catch (error) {
      throw error;
    }

    this._nav = nav;

    p.observe(window);
  }

  public async openPublication(
    publicationURL: string,
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
      preferencesJson !== undefined ? JSON.stringify(preferencesJson) : '{}';

    let preferences = setPreferencesFromString(preferencesJsonString);

    const configuration: EpubNavigatorConfiguration = {
      preferences,
      defaults,
    };

    try {
      if (this._publication == undefined) {
        const { manifest, fetcher } = await this.fetchManifest(publicationURL);
        this._publication = new Publication({ manifest, fetcher });
      }
      if (isAudiobook) {
        // Initialize WebAudioEngine for audiobooks
        // TODO: wip

        // If the audiobook has text, initialize the navigator for text display
        if (hasText) {
          await this.initializeNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            configuration
          );
        }
      } else {
        // Initialize EpubNavigator for ebooks
        await this.initializeNavigatorAndPeripherals(
          container,
          this._publication,
          initialPosition,
          configuration
        );
      }
    } catch (error) {
      this.closePublication();
      throw new Error('Error opening publication: ' + error);
    }
  }

  public updatePreferences(newPreferencesString: string) {
    if (!this._nav) {
      throw new Error('Navigator is not initialized');
    }
    updatePreferences(newPreferencesString, this._nav);
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
