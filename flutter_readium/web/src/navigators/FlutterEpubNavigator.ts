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
} from "../decorations/decorationFrameUtils";
import { injectFlutterReadiumHelperScripts } from "../utils/iframeInjection";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { tryBuildImageTapPayload } from "../utils/ImageTapDetector";
import {
  enrichWithTotalProgression,
  enrichWithTocHref,
  flattenToc,
} from "./locatorEnrich";
import {
  scrollVisibleIframes,
  handleExternalLocator,
  buildTextSelectionPayload,
} from "./navigatorUtils";

const log = createLogger("EpubNav");

export class FlutterEpubNavigator {
  /**
   * Pre-computed position list for this publication.
   * Exposed here so callers that need positions alongside the navigator can
   * receive both via a single `await FlutterEpubNavigator.create(...)` call
   * rather than fetching them again from the manifest separately.
   */
  readonly positions: Locator[];

  private constructor(positions: Locator[]) {
    this.positions = positions;
  }

  static async create(
    container: HTMLElement,
    publication: ReadiumPublication,
    initialPosition: Locator | undefined,
    preferencesJsonString: string,
    setNav: (nav: EpubNavigator | WebPubNavigator) => void,
    setPositions?: (positions: Locator[]) => void,
    emitImageTapped?: (json: string) => void,
    onFrameLoaded?: (wnd: Window) => void,
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
        } else if (direction === "up" || direction === "down") {
          scrollVisibleIframes(direction);
        }
      },
      menu: (_show) => {},
      goProgression: (_shiftKey) => {
        nav.goForward(true, () => {});
      },
    });

    const handleImageTapEvent = function (e: FrameClickEvent): boolean {
      if (emitImageTapped) {
        const payload = tryBuildImageTapPayload(e, nav, publication);
        if (payload !== null) {
          emitImageTapped(payload);
          return true;
        }
      }
      return false;
    };

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
              onFrameLoaded?.(frameManager.window);
            }
          }
        );
        p.observe(window);
      },
      positionChanged: (_locator: Locator): void => {
        emitTextLocatorDebounced(
          enrichWithTocHref(
            enrichWithTotalProgression(_locator, totalPositions),
            flatTocItems
          )
        );
      },
      tap: handleImageTapEvent,
      click: handleImageTapEvent,
      zoom: function (_scale: number): void {},
      miscPointer: function (_amount: number): void {},
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

    return new FlutterEpubNavigator(positions);
  }
}
