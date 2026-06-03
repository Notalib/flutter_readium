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
import Peripherals from "../utils/Peripherals";
import {
  defaults,
  initializeWebPubPreferencesFromString,
} from "../preferences/FlutterWebPubPreferences";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { injectDecorationOverrides } from "../decorations/decorationOverrides";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { enrichWithTotalProgression } from "./locatorEnrich";
import {
  scrollVisibleIframes,
  handleExternalLocator,
  buildTextSelectionPayload,
} from "./navigatorUtils";

const log = createLogger("WebPubNav");

export class FlutterWebPubNavigator {
  // This class is a static factory only. The constructed navigator is delivered
  // via the `setNav` callback so that ReadiumReader can hold it as the raw
  // upstream type (WebPubNavigator) without wrapping.

  static async create(
    container: HTMLElement,
    publication: ReadiumPublication,
    initialPosition: Locator | undefined,
    preferencesJsonString: string,
    setNav: (nav: WebPubNavigator) => void
  ): Promise<void> {
    log.info("Initializing WebPubNavigator");
    const preferences = initializeWebPubPreferencesFromString(preferencesJsonString);

    log.debug("WebPub preferences", preferences);

    // The WebPub navigator derives `position` from the resource index in the
    // reading order. Mirror that for `totalProgression`.
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
        } else if (direction === "up" || direction === "down") {
          scrollVisibleIframes(direction);
        }
      },
      menu: (_show) => {},
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
        handleExternalLocator(locator.href);
        return false;
      },
      contentProtection: function (_type: string, _data: any): void {},
      peripheral: function (_data: KeyboardPeripheralEventData): void {},
      contextMenu: function (_data: ContextMenuEvent): void {},
      textSelected: function (_selection: BasicTextSelection): void {
        window.onTextSelectedCallback?.(
          buildTextSelectionPayload(nav.currentLocator, _selection)
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
      log.info("WebPubNavigator loaded");
    } catch (error) {
      log.error("Failed to load WebPubNavigator:", error);
      throw error;
    }

    setNav(nav);

    p.observe(window);
  }
}
