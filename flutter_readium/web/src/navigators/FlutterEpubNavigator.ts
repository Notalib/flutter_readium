import {
  BasicTextSelection,
  ContextMenuEvent,
  FrameClickEvent,
} from "@readium/navigator-html-injectables";
import { KeyboardPeripheralEventData } from "@readium/navigator";
import {
  EpubNavigator,
  EpubNavigatorListeners,
  EpubNavigatorConfiguration,
  WebPubNavigator,
  FrameManager,
  FXLFrameManager,
} from "@readium/navigator";
import { Locator, LocatorLocations, Link } from "@readium/shared";
import Peripherals from "../utils/Peripherals";
import {
  defaults,
  initializeEpubPreferencesFromString,
} from "../preferences/FlutterEpubPreferences";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import {
  injectDecorationOverrides,
} from "../decorations/decorationOverrides";
import { injectFlutterReadiumHelperScripts } from "../utils/iframeInjection";
import { createLogger } from "../utils/ReadiumPluginLogger";
import {
  enrichWithTotalProgression,
  enrichWithTocHref,
  flattenToc,
} from "./locatorEnrich";

const log = createLogger("EpubNav");

export class FlutterEpubNavigator {
  readonly underlying: EpubNavigator | WebPubNavigator;
  readonly positions: Locator[];

  private constructor(nav: EpubNavigator | WebPubNavigator, positions: Locator[]) {
    this.underlying = nav;
    this.positions = positions;
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
    setNav: (nav: EpubNavigator | WebPubNavigator) => void,
    setPositions?: (positions: Locator[]) => void
  ): Promise<FlutterEpubNavigator> {
    log.info("Initializing EpubNavigator");
    let positions = await publication.positionsFromManifest();

    if (positions.length === 0) {
      log.warn("No positions from manifest, falling back to readingOrder");
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

    const preferences = initializeEpubPreferencesFromString(preferencesJsonString);

    // 200 ms trailing-edge debounce keeps bookmarks responsive without spamming consumers.
    const TEXT_LOCATOR_DEBOUNCE_MS = 200;
    let textLocatorTimer: ReturnType<typeof setTimeout> | undefined;
    const emitTextLocatorDebounced = (locator: Locator) => {
      if (textLocatorTimer !== undefined) clearTimeout(textLocatorTimer);
      textLocatorTimer = setTimeout(() => {
        textLocatorTimer = undefined;
        window.updateTextLocator?.(JSON.stringify(locator.serialize()));
      }, TEXT_LOCATOR_DEBOUNCE_MS);
    };

    const totalPositions = positions.length;
    const flatTocItems = flattenToc(publication.manifest.toc?.items ?? []);
    log.debug(`TOC flattened: ${flatTocItems.length} entries, positions: ${positions.length}`);

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
      menu: (_show) => {},
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
              log.debug("Injecting helpers into FrameManager for:", frameManager.window.location.href);
              p.observe(frameManager.window);
              injectDecorationOverrides(frameManager.window);
              const tocFragmentIds = flatTocItems
                .map((l) => {
                  const hash = l.href.indexOf("#");
                  return hash !== -1 ? l.href.slice(hash + 1) : "";
                })
                .filter((id) => id.length > 0);
              injectFlutterReadiumHelperScripts(frameManager.window, tocFragmentIds);
            }
          }
        );
        p.observe(window);
      },
      positionChanged: (_locator: Locator): void => {
        window.focus();
        emitTextLocatorDebounced(
          enrichWithTocHref(
            enrichWithTotalProgression(_locator, totalPositions),
            flatTocItems
          )
        );
      },
      tap: function (_e: FrameClickEvent): boolean {
        return false;
      },
      click: function (_e: FrameClickEvent): boolean {
        return false;
      },
      zoom: function (_scale: number): void {},
      miscPointer: function (_amount: number): void {},
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

    // Resolve position-less initial locator (e.g. from sync-narration).
    let resolvedInitialPosition = initialPosition;
    if (initialPosition && initialPosition.locations?.position == null) {
      const chapPos = positions.find((p) => p.href === initialPosition.href);
      if (chapPos) {
        resolvedInitialPosition = new Locator({
          href: initialPosition.href,
          type: initialPosition.type,
          title: initialPosition.title ?? chapPos.title,
          locations: new LocatorLocations({
            position: chapPos.locations?.position,
            fragments: initialPosition.locations?.fragments,
            otherLocations: initialPosition.locations?.otherLocations,
          }),
        });
        log.debug(
          `Resolved position-less initial locator: ${initialPosition.href} → position ${chapPos.locations?.position}`
        );
      } else {
        log.warn(`Couldn't resolve position for initial locator: ${initialPosition.href}, falling back to href-only lookup (may be inaccurate)`);
      }
    }

    const nav = new EpubNavigator(
      container,
      publication,
      listeners,
      positions,
      resolvedInitialPosition,
      configuration
    );

    try {
      await nav.load();
      log.info("EpubNavigator loaded");
    } catch (error) {
      log.error("Failed to load EpubNavigator:", error);
      throw error;
    }

    setNav(nav);
    setPositions?.(positions);

    p.observe(window);

    return new FlutterEpubNavigator(nav, positions);
  }
}
