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
  console.log("Initializing WebPubNavigator");
  let preferences = initializeWebPubPreferencesFromString(
    preferencesJsonString
  );

  console.log('Initialized WebPub preferences', preferences);

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
        }
      });
      p.observe(window);
    },
    positionChanged: (_locator: Locator): void => {
      window.focus();

      (window as any).updateTextLocator?.(JSON.stringify(_locator));
    },
    tap: function (_e: FrameClickEvent): boolean {
      console.log("tap event received in WebPubNavigator");

      return false;
    },
    click: function (_e: FrameClickEvent): boolean {
      console.log("click event received in WebPubNavigator");
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
        console.warn("Unhandled locator", locator);
      }
      return false;
    },
    contentProtection: function (_type: string, _data: any): void {},
    peripheral: function (_data: KeyboardPeripheralEventData): void {},
    contextMenu: function (_data: ContextMenuEvent): void {},
    textSelected: function (_selection: BasicTextSelection): void {
      // Notify Dart about the text selection
      const currentLocator = nav.currentLocator;
      const locatorJson = {
        href: currentLocator.href,
        type: currentLocator.type,
        locations: currentLocator.locations,
        text: { highlight: _selection.text },
      };
      (window as any).onTextSelectedCallback?.(
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
