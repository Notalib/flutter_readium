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
// import { initializeWebPubNavigatorAndPeripherals } from "../WebPub/webpubNavigator";

export async function initializeEpubNavigatorAndPeripherals(
  container: HTMLElement,
  publication: ReadiumPublication,
  initialPosition: Locator | undefined = undefined,
  preferencesJsonString: string,
  setNav: (nav: EpubNavigator | WebPubNavigator) => void,
  setPositions?: (positions: Locator[]) => void
) {
  console.log("Initializing EpubNavigator");
  let positions = await publication.positionsFromManifest();

  if (positions.length === 0) {
    // Use readingOrder if positionListLink is undefined
    // TODO: this is a workaround, consider using initializeWebPubNavigatorAndPeripherals as fallback instead
    // webpub does not required a position list
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

  // Build a flat TOC list once per session so we can enrich every emitted
  // locator with `tocHref` in `locations.otherLocations` — matching the
  // contract the native plugins (iOS / Android) already use. Without this,
  // example-app features like next/previous-chapter (which read
  // `locator.locations.tocHref`) never get a starting reference.
  const flatToc = flattenToc(publication.manifest.toc?.items ?? []);

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
            p.observe(frameManager.window);
          }
        }
      );
      p.observe(window);
    },
    positionChanged: (_locator: Locator): void => {
      window.focus();
      emitTextLocatorDebounced(enrichWithTocHref(_locator, flatToc));
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
      window.onTextSelectedCallback?.(
        JSON.stringify({ locator: locatorJson, selectedText: _selection.text })
      );
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
    // TODO: check if necessary to rethrow
    throw error;
  }

  setNav(nav);
  setPositions?.(positions);

  p.observe(window);
}

/**
 * Walks the `toc` link tree and returns a flat list of every entry. The shared
 * Links collection doesn't expose a flatten helper, so we recurse manually.
 */
function flattenToc(items: Link[]): Link[] {
  const out: Link[] = [];
  for (const link of items) {
    out.push(link);
    // `children` is a `Links` instance (not a plain array); recurse over `.items`.
    const children = link.children?.items;
    if (children && children.length > 0) {
      out.push(...flattenToc(children));
    }
  }
  return out;
}

/**
 * Adds `tocHref` to `locator.locations.otherLocations` so the Dart-side
 * `Locator.locations.tocHref` getter returns the current chapter's TOC href.
 *
 * Matches by resource href (strips any `#fragment`). If the publication's TOC
 * has multiple entries pointing into the same resource, the first one wins —
 * good enough for the next/previous-chapter use case. A finer-grained match
 * (by fragment / cssSelector) would require the iframe to surface the visible
 * element's id, which the ts-toolkit doesn't expose today.
 */
function enrichWithTocHref(locator: Locator, flatToc: Link[]): Locator {
  if (flatToc.length === 0) return locator;
  const tocHref = findCurrentTocHref(locator.href, flatToc);
  if (!tocHref) return locator;
  // Avoid clobbering an existing tocHref (e.g. set by an upstream caller).
  const existing = locator.locations?.otherLocations ?? new Map<string, any>();
  if (existing.get("tocHref") === tocHref) return locator;
  const merged = new Map(existing);
  merged.set("tocHref", tocHref);
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    text: locator.text,
    locations: new LocatorLocations({
      fragments: locator.locations?.fragments,
      progression: locator.locations?.progression,
      position: locator.locations?.position,
      totalProgression: locator.locations?.totalProgression,
      otherLocations: merged,
    }),
  });
}

function findCurrentTocHref(
  resourceHref: string,
  flatToc: Link[]
): string | undefined {
  const targetPath = stripFragment(resourceHref);
  const match = flatToc.find((l) => stripFragment(l.href) === targetPath);
  return match?.href;
}

function stripFragment(href: string): string {
  const i = href.indexOf("#");
  return i === -1 ? href : href.substring(0, i);
}
