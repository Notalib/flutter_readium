import {
  BasicTextSelection,
  FrameClickEvent,
  Width,
  Layout,
} from "@readium/navigator-html-injectables";
import {
  EpubNavigator,
  EpubNavigatorListeners,
  EpubNavigatorConfiguration,
  WebPubNavigator,
  FrameManager,
  FXLFrameManager,
} from "@readium/navigator";
import {
  Publication,
  Locator,
  LocatorLocations,
  Link,
  LocatorText,
} from "@readium/shared";
import Peripherals from "../peripherals";
import {
  defaults,
  initializeEpubPreferencesFromString,
} from "./epubPreferences";
import { highlightSelection } from "../helpers";
// import { initializeWebPubNavigatorAndPeripherals } from "../WebPub/webpubNavigator";

export async function initializeEpubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: Publication,
  initialPosition: Locator | undefined = undefined,
  preferencesJsonString: string,
  setNav: (nav: EpubNavigator | WebPubNavigator) => void
) {
  console.log("Initializing EpubNavigator");
  let positions = await publication.positionsFromManifest();

  if (positions.length === 0) {
    // Use readingOrder if positionListLink is undefined
    // TODO: this is a workaround, consider using initializeWebPubPreferencesFromString as fallback instead
    positions = publication.manifest.readingOrder.items.map(
      (link: Link, index: number) => {
        return new Locator({
          href: link.href,
          type: link.type ?? "text/html",
          title: link.title,
          locations: new LocatorLocations({
            position: index + 1,
          }),
        });
      }
    );
  }

  let preferences = initializeEpubPreferencesFromString(preferencesJsonString);

  const configuration: EpubNavigatorConfiguration = {
    preferences,
    defaults,
  };

  const p = new Peripherals({
    moveTo: (direction) => {
      if (direction === "right") {
        nav.goRight(true, () => {});
      } else if (direction === "left") {
        nav.goLeft(true, () => {});
      } else if (direction === "up") {
        const iframes = document.querySelectorAll(".readium-navigator-iframe");
        iframes.forEach((iframe) => {
          if (iframe instanceof HTMLIFrameElement) {
            if (iframe.style.visibility !== "hidden") {
              iframe.contentWindow?.scrollBy(0, -100);
            }
          }
        });
      } else if (direction === "down") {
        const iframes = document.querySelectorAll(".readium-navigator-iframe");
        iframes.forEach((iframe) => {
          if (iframe instanceof HTMLIFrameElement) {
            if (iframe.style.visibility !== "hidden") {
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
    scroll: function (_amount: number): void {},
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
        href.startsWith("http://") ||
        href.startsWith("https://") ||
        href.startsWith("mailto:") ||
        href.startsWith("tel:")
      ) {
        if (confirm(`Open "${href}" ?`)) window.open(href, "_blank");
      } else {
        console.warn("Unhandled locator", locator);
      }
      return false;
    },
    textSelected: function (_selection: BasicTextSelection): void {
      highlightSelection(nav, publication, _selection);
    },
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
