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
import { Locator, Link } from "@readium/shared";
import Peripherals from "../utils/Peripherals";
import {
  defaults,
  initializeWebPubPreferencesFromString,
} from "../preferences/FlutterWebPubPreferences";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { injectDecorationOverrides } from "../decorations/decorationOverrides";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { enrichWithTotalProgression } from "./locatorEnrich";

const log = createLogger("WebPubNav");

export class FlutterWebPubNavigator {
  readonly underlying: WebPubNavigator;

  private constructor(nav: WebPubNavigator) {
    this.underlying = nav;
  }

  get currentLocator(): Locator {
    return this.underlying.currentLocator;
  }

  goRight(animated: boolean, completion: () => void): void {
    this.underlying.goRight(animated, completion);
  }

  goLeft(animated: boolean, completion: () => void): void {
    this.underlying.goLeft(animated, completion);
  }

  goForward(animated: boolean, completion: () => void): void {
    this.underlying.goForward(animated, completion);
  }

  goBackward(animated: boolean, completion: () => void): void {
    this.underlying.goBackward(animated, completion);
  }

  goLink(link: Link, animated: boolean, completion: (ok: boolean) => void): void {
    this.underlying.goLink(link, animated, completion);
  }

  go(locator: Locator, animated: boolean, completion: (ok: boolean) => void): void {
    this.underlying.go(locator, animated, completion);
  }

  destroy(): void {
    this.underlying.destroy();
  }

  static async create(
    container: HTMLElement,
    publication: ReadiumPublication,
    initialPosition: Locator | undefined,
    preferencesJsonString: string,
    setNav: (nav: WebPubNavigator) => void
  ): Promise<FlutterWebPubNavigator> {
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

    return new FlutterWebPubNavigator(nav);
  }
}
