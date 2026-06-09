import {
  BasicTextSelection,
  ContextMenuEvent,
  FrameClickEvent,
} from "@readium/navigator-html-injectables";
import { KeyboardPeripheralEventData } from "@readium/navigator";
import {
  WebPubFrameManager,
  WebPubNavigator,
  WebPubNavigatorConfiguration,
  WebPubNavigatorListeners,
} from "@readium/navigator";
import { Locator } from "@readium/shared";
import Peripherals from "../peripherals";
import {
  defaults,
  initializeWebPubPreferencesFromString,
} from "./webPubPrefences";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { injectDecorationOverrides } from "../helpers";
import { createLogger } from "../logger";
import { enrichWithTotalProgression } from "../Epub/epubNavigator";

const log = createLogger("WebPubNav");

// TODO:
// There is a webpub from readiums publication-server called molly hopper that is an accessible epub and it doesn't quite work
// but I dont know if it's because of the pub or this project

export async function initializeWebPubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: ReadiumPublication,
  initialPosition: Locator | undefined = undefined,
  preferencesJsonString: string,
  setNav: (nav: WebPubNavigator) => void
) {
  log.info("Initializing WebPubNavigator");
  let preferences = initializeWebPubPreferencesFromString(
    preferencesJsonString
  );

  log.debug("WebPub preferences", preferences);

  // The WebPub navigator doesn't precompute a positions list; it derives
  // `position` from the resource index in the reading order (see
  // WebPubNavigator.createCurrentLocator → `position: currentIndex + 1`).
  // Mirror that for `totalProgression` so consumers get a value even when
  // the publication has no positionList in its manifest.
  const totalPositions = publication.readingOrder.items.length;

  const configuration: WebPubNavigatorConfiguration = {
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
        // TODO: check for scroll mode first
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
      // TODO: figure out if this is needed or should be handled completely on the flutter side
    },
    goProgression: (_shiftKey) => {
      nav.goForward(true, () => {});
    },
  });

  const listeners: WebPubNavigatorListeners = {
    scroll: function (_amount: number): void {},
    frameLoaded: function (_wnd: Window): void {
      nav._cframes.forEach((frameManager: WebPubFrameManager | undefined) => {
        if (frameManager) {
          p.observe(frameManager.window);
          injectDecorationOverrides(frameManager.window);
        }
      });
      p.observe(window);
    },
    positionChanged: (_locator: Locator): void => {
      window.focus();

      const enriched = enrichWithTotalProgression(_locator, totalPositions);
      // Use Locator.serialize() so otherLocations Map entries survive the
      // JSON round-trip (plain JSON.stringify silently drops Map values).
      window.updateTextLocator?.(JSON.stringify(enriched.serialize()));
    },
    tap: function (_e: FrameClickEvent): boolean {
      log.debug("tap event");

      return false;
    },
    click: function (_e: FrameClickEvent): boolean {
      log.debug("click event");
      return false;
    },
    zoom: function (_scale: number): void {},
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
        log.warn("Unhandled locator href:", href);
      }
      return false;
    },
    contentProtection: function (_type: string, _data: any): void {},
    peripheral: function (_data: KeyboardPeripheralEventData): void {},
    contextMenu: function (_data: ContextMenuEvent): void {},
    textSelected: function (_selection: BasicTextSelection): void {
      // Notify Dart about the text selection.
      // Use serialize() so otherLocations Map entries survive stringification,
      // then override text with the active selection highlight.
      const locatorJson = {
        ...nav.currentLocator.serialize(),
        text: { highlight: _selection.text },
      };
      window.onTextSelectedCallback?.(
        JSON.stringify({ locator: locatorJson, selectedText: _selection.text })
      );
    },
  };

  const nav = new WebPubNavigator(
    container,
    publication,
    listeners,
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
