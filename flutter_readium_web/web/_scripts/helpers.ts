import {
  BasicTextSelection,
  FrameClickEvent,
} from '@readium/navigator-html-injectables';
import {
  EpubNavigator,
  EpubNavigatorListeners,
  EpubNavigatorConfiguration,
  FrameManager,
  FXLFrameManager,
} from '@readium/navigator';
import {
  Publication,
  Locator,
  Manifest,
  LocatorLocations,
  Link,
  Fetcher,
  HttpFetcher,
} from '@readium/shared';
import Peripherals from './peripherals';

export async function fetchManifest(publicationURL: string) {
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

export async function initializeNavigatorAndPeripherals(
  container: HTMLElement,
  publication: Publication,
  initialPosition: Locator | undefined = undefined,
  configuration: EpubNavigatorConfiguration,
  setNav: (nav: EpubNavigator) => void
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
      } else if (direction === 'up') {
        const iframes = document.querySelectorAll('.readium-navigator-iframe');
        iframes.forEach((iframe) => {
          if (iframe instanceof HTMLIFrameElement) {
            if (iframe.style.visibility !== 'hidden') {
              iframe.contentWindow?.scrollBy(0, -100);
            }
          }
        });
      } else if (direction === 'down') {
        const iframes = document.querySelectorAll('.readium-navigator-iframe');
        iframes.forEach((iframe) => {
          if (iframe instanceof HTMLIFrameElement) {
            if (iframe.style.visibility !== 'hidden') {
              iframe.contentWindow?.scrollBy(0, 100);
            }
          }
        });
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

  const nav = new EpubNavigator(
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

  setNav(nav);

  p.observe(window);
}
