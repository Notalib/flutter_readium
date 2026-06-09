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
import Peripherals from "../peripherals";
import {
  defaults,
  initializeEpubPreferencesFromString,
} from "./epubPreferences";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { injectDecorationOverrides, injectFlutterReadiumHelperScripts } from "../helpers";
import { createLogger } from "../logger";
import {
  flattenToc,
  enrichLocatorWithTocHref,
} from "../helpers/tocHref";
// import { initializeWebPubNavigatorAndPeripherals } from "../WebPub/webpubNavigator";

const log = createLogger("EpubNav");

export async function initializeEpubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: ReadiumPublication,
  initialPosition: Locator | undefined = undefined,
  preferencesJsonString: string,
  setNav: (nav: EpubNavigator | WebPubNavigator) => void,
  setPositions?: (positions: Locator[]) => void
) {
  log.info("Initializing EpubNavigator");
  let positions = await publication.positionsFromManifest();

  if (positions.length === 0) {
    // Use readingOrder if positionListLink is undefined
    // TODO: this is a workaround, consider using initializeWebPubNavigatorAndPeripherals as fallback instead
    // webpub does not required a position list
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

  let preferences = initializeEpubPreferencesFromString(preferencesJsonString);

  // Trailing-edge debounce for positionChanged -> updateTextLocator. In scroll
  // mode the ts-toolkit emits `progress` events on every rAF tick (~60Hz), which
  // floods the Dart-side `onTextLocatorChanged` stream with redundant updates.
  // Native (iOS / Android) navigators emit one event per page change, so we
  // match that cadence here by waiting for scroll/pagination activity to settle
  // before forwarding the final locator. 200 ms keeps bookmarks responsive
  // without spamming consumers.
  const TEXT_LOCATOR_DEBOUNCE_MS = 200;
  let textLocatorTimer: ReturnType<typeof setTimeout> | undefined;
  const emitTextLocatorDebounced = (locator: Locator) => {
    if (textLocatorTimer !== undefined) clearTimeout(textLocatorTimer);
    textLocatorTimer = setTimeout(() => {
      textLocatorTimer = undefined;
      // Use Locator.serialize() so otherLocations entries (e.g. `tocHref`)
      // are inlined into `locations`. Plain JSON.stringify drops Map entries.
      window.updateTextLocator?.(JSON.stringify(locator.serialize()));
    }, TEXT_LOCATOR_DEBOUNCE_MS);
  };

  const totalPositions = positions.length;

  // Build a flat TOC list once per session so we can enrich every emitted
  // locator with `tocHref` in `locations.otherLocations` — matching the
  // contract the native plugins (iOS / Android) already use. Without this,
  // example-app features like next/previous-chapter (which read
  // `locator.locations.tocHref`) never get a starting reference.
  const flatToc = flattenToc(publication.manifest.toc?.items ?? []);
  log.debug(`TOC flattened: ${flatToc.length} entries, positions: ${positions.length}`);

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
            log.debug("Injecting helpers into FrameManager for:", frameManager.window.location.href);
            p.observe(frameManager.window);
            injectDecorationOverrides(frameManager.window);
            // Inject the same helper bundle (JS + CSS) that native iOS/Android
            // inject into the EPUB webview. This sets up the comic pan/zoom
            // overlay, `window.flutterReadium` tools, responsive tables, etc.
            const tocFragmentIds = flatToc
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
        enrichLocatorWithTocHref(
          enrichWithTotalProgression(_locator, totalPositions),
          flatToc
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
        log.warn("Unhandled locator href:", href);
      }
      return false;
    },
    contentProtection: function (_type: string, _data: any): void {},
    peripheral: function (_data: KeyboardPeripheralEventData): void {},
    contextMenu: function (_data: ContextMenuEvent): void {},
    textSelected: function (_selection: BasicTextSelection): void {
      // Notify Dart about the text selection.
      // Use serialize() so otherLocations Map entries (e.g. tocHref) survive stringification,
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

  // EpubNavigator requires locations.position to be a number for its internal
  // position-list lookup. Locators saved during sync-narration playback only
  // carry href + fragments (no position number) — patch in the position from
  // the nearest chapter entry so the constructor doesn't throw, while
  // preserving the original fragments so the navigator scrolls to the right
  // element within the chapter.
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
    // TODO: check if necessary to rethrow
    throw error;
  }

  setNav(nav);
  setPositions?.(positions);

  p.observe(window);
}

/**
 * Adds `totalProgression` to the emitted locator. The upstream ts-toolkit
 * navigator never populates this field — `Locator.serialize()` only forwards
 * it when already set — so we compute it from the positions list we already
 * have. Formula matches the upstream Readium positions-service convention:
 *
 *   (position - 1 + progression) / totalPositions
 *
 * `progression` (within-resource) falls back to 0 when undefined, which makes
 * the value coincide with `(position - 1) / totalPositions` for paginated
 * navigators that don't emit a sub-resource progression.
 */
export function enrichWithTotalProgression(
  locator: Locator,
  totalPositions: number
): Locator {
  if (totalPositions <= 0) return locator;
  const position = locator.locations?.position;
  if (position === undefined || position <= 0) return locator;
  const progression = locator.locations?.progression ?? 0;
  const raw = (position - 1 + progression) / totalPositions;
  const totalProgression = Math.min(1, Math.max(0, raw));
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    text: locator.text,
    locations: new LocatorLocations({
      fragments: locator.locations?.fragments,
      progression: locator.locations?.progression,
      position: locator.locations?.position,
      totalProgression,
      otherLocations: locator.locations?.otherLocations,
    }),
  });
}

// flattenToc, enrichLocatorWithTocHref, and their helpers are now in
// ../helpers/tocHref (imported above). The local copies have been removed.
