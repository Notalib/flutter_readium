/**
 * Media Overlay navigator for the web platform.
 *
 * Mirrors FlutterMediaOverlayNavigator in the Swift/Kotlin plugin layers.
 *
 * Strategy:
 *  1. Parse the EPUB's Sync Narration JSON alternates into a flat item list.
 *  2. Build a synthetic audio reading-order (one Link per unique audio file).
 *  3. Hand the synthetic publication to AudioNavigator (same path as audiobooks).
 *  4. Intercept positionChanged to map audio time -> text locator and emit dual
 *     state/locator events matching iOS/Android behaviour.
 */

import { Link, Locator, Manifest, Profile } from "@readium/shared";
import { AudioNavigator } from "@readium/navigator";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { AudioLocatorMapper, FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import {
  SyncNarrationItem,
  combinedLocatorForItem,
  findItemByAudioTime,
  parseSyncNarration,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "../mediaoverlay/syncNarration";
import { parseGuidedNavigation } from "../mediaoverlay/guidedNavigation";

const log = createLogger("MediaOverlay");

/**
 * Initialises a Media Overlay session backed by Sync Narration JSON alternates.
 *
 * @param publication            The EPUB publication (must have Sync Narration alternates).
 * @param initialLocator         Optional starting text locator (will be mapped to audio time).
 * @param prefsJson              Dart AudioPreferences JSON string.
 * @param setNav                 Callback invoked once AudioNavigator is ready. Receives the
 *                               navigator and the parsed SyncNarrationItem list so callers can
 *                               run text→audio mapping on subsequent navigation events.
 * @param onTextLocatorChanged   Optional callback fired each time the active Sync Narration
 *                               cue advances to a new text locator. Used by ReadiumReader to
 *                               apply utterance-level decorations on the visual navigator.
 *                               Receives the text locator and the cue duration in milliseconds.
 */
export async function initializeMediaOverlayNavigator(
  publication: ReadiumPublication,
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: (nav: AudioNavigator, items: SyncNarrationItem[]) => void,
  onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void
): Promise<void> {
  const items = await parseSyncNarration(publication);
  return _initializeFromItems(
    publication, items, initialLocator, prefsJson, setNav, onTextLocatorChanged, "SyncNarration"
  );
}

/**
 * Initialises a Media Overlay session backed by Guided Navigation JSON.
 *
 * Same downstream pipeline as `initializeMediaOverlayNavigator`; only the
 * parser differs. Guided Navigation takes precedence over Sync Narration when
 * both are present — matching native behaviour (iOS getSyncNarrationMediaOverlays).
 */
export async function initializeGuidedNavigationNavigator(
  publication: ReadiumPublication,
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: (nav: AudioNavigator, items: SyncNarrationItem[]) => void,
  onTextLocatorChanged?: (locator: Locator, durationMs: number | undefined) => void
): Promise<void> {
  const items = await parseGuidedNavigation(publication);
  return _initializeFromItems(
    publication, items, initialLocator, prefsJson, setNav, onTextLocatorChanged, "GuidedNavigation"
  );
}

async function _initializeFromItems(
  publication: ReadiumPublication,
  items: SyncNarrationItem[],
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: (nav: AudioNavigator, items: SyncNarrationItem[]) => void,
  onTextLocatorChanged: ((locator: Locator, durationMs: number | undefined) => void) | undefined,
  sourceLabel: string
): Promise<void> {
  log.info(
    `Initializing MediaOverlayNavigator (source: ${sourceLabel})`,
    initialLocator ? `from text locator ${initialLocator.href}` : "(no initial locator)"
  );

  if (items.length === 0) {
    log.warn(`No items found from ${sourceLabel}; aborting.`);
    return;
  }
  const uniqueAudioFiles = new Set(items.map((i) => i.audioHref)).size;
  log.info(
    `Parsed ${items.length} items across ${uniqueAudioFiles} audio file(s)`
  );

  const audioReadingOrder = _buildAudioReadingOrder(items, publication);
  log.info(
    `Built synthetic audio reading order with ${audioReadingOrder.length} entries`,
    audioReadingOrder.length > 0
      ? `(first=${audioReadingOrder[0].href}, last=${audioReadingOrder[audioReadingOrder.length - 1].href})`
      : ""
  );

  const syntheticPub = _buildAudiobookPublication(publication, audioReadingOrder);

  // Resolve relative audioHref values in items to the absolute form used in the
  // reading order. Narration JSON stores relative hrefs ("chap.mp3") but the
  // reading order and every locator the AudioNavigator emits use absolute URLs
  // ("https://.../chap.mp3"). AudioNavigator does exact href lookups, so all
  // three consumers — the mapper, textLocatorToAudioLocator (initial seek /
  // goToLocator), and the setNav callback — must see the same absolute hrefs.
  const resolvedItems = _resolveItemHrefs(items, audioReadingOrder);

  const audioInitialLocator = initialLocator
    ? textLocatorToAudioLocator(resolvedItems, initialLocator)
    : undefined;
  if (initialLocator) {
    log.info(
      audioInitialLocator
        ? `Initial text locator mapped to audio ${audioInitialLocator.href} ${audioInitialLocator.locations?.fragments?.[0] ?? ""}`
        : `Initial text locator could not be mapped to an audio item — starting at beginning`
    );
  }

  const mapper: AudioLocatorMapper = (_nav, audioLocator) => {
    const resolvedTime = audioLocator.locations?.time() ?? _nav.currentTime;
    const item = findItemByAudioTime(resolvedItems, audioLocator.href, resolvedTime);
    if (item) {
      return {
        stateLocator: combinedLocatorForItem(item, audioLocator),
        textLocator: textLocatorForItem(item),
      };
    }
    return { stateLocator: audioLocator };
  };

  // Wrap the caller's callback to enrich it with the cue duration.
  // The AudioLocatorMapper knows which SyncNarrationItem is active, but the
  // callback signature at the audioNavigator layer doesn't carry that info.
  // Instead, we re-derive the item here from the text locator fragment by
  // matching against resolvedItems — same lookup the mapper does, just keyed on
  // the text side.
  const wrappedCallback:
    | ((locator: Locator, durationMs: number | undefined) => void)
    | undefined = onTextLocatorChanged
    ? (locator, _ignored) => {
        const fragId = locator.locations?.fragments?.[0];
        const item = fragId
          ? resolvedItems.find((i) => i.textId === fragId)
          : undefined;
        const durationMs =
          item?.audioStart != null && item?.audioEnd != null
            ? (item.audioEnd - item.audioStart) * 1000
            : undefined;
        log.debug(
          `[mediaOverlay] cue fragment="${fragId ?? "(none)"}" ` +
          `item=${item ? `audioStart=${item.audioStart} audioEnd=${item.audioEnd}` : "NOT FOUND"} ` +
          `→ durationMs=${durationMs ?? "undefined"}`
        );
        onTextLocatorChanged(locator, durationMs);
      }
    : undefined;

  await FlutterAudioNavigator.create(
    syntheticPub,
    audioInitialLocator,
    prefsJson,
    (nav: AudioNavigator) => setNav(nav, resolvedItems),
    mapper,
    wrappedCallback,
    // Media overlay cue synchronisation requires finer granularity than the
    // Dart-side updateIntervalSecs preference (which controls the progress bar).
    // 100ms keeps panel panning within one frame of the audio cue boundary.
    100
  );

  if (wrappedCallback) {
    const fragment = audioInitialLocator?.locations?.fragments?.[0];
    const initTime = fragment?.startsWith("t=") ? parseFloat(fragment.slice(2)) : 0;
    const initHref = audioInitialLocator?.href ?? resolvedItems[0]?.audioHref;
    const initItem = initHref
      ? findItemByAudioTime(resolvedItems, initHref, initTime) ?? resolvedItems[0]
      : resolvedItems[0];
    if (initItem) {
      const initDurationMs =
        initItem.audioStart != null && initItem.audioEnd != null
          ? (initItem.audioEnd - initItem.audioStart) * 1000
          : undefined;
      wrappedCallback(textLocatorForItem(initItem), initDurationMs);
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/**
 * Resolves relative `audioHref` values in items to the absolute hrefs used in
 * the synthetic reading order. The narration JSON stores relative paths; the
 * reading order and AudioNavigator locators use absolute URLs. Any item whose
 * relative href matches a reading-order entry via suffix comparison is updated
 * in place; unmatched items are left unchanged.
 */
function _resolveItemHrefs(
  items: SyncNarrationItem[],
  audioReadingOrder: Link[]
): SyncNarrationItem[] {
  return items.map((item) => {
    const absLink = audioReadingOrder.find(
      (l) => l.href === item.audioHref || l.href.endsWith("/" + item.audioHref)
    );
    return absLink ? { ...item, audioHref: absLink.href } : item;
  });
}

/**
 * One Link per unique audio file, ordered by first appearance in reading order.
 *
 * Duration policy: prefer the largest reading-order item duration declared by
 * the publication's manifest for items that map to this audio file; fall back
 * to the sum of (audioEnd - audioStart) of all cues in that file. The manifest
 * value is authoritative when present because cues can leave gaps (silence,
 * intro/outro) that the cue-sum would underestimate.
 */
function _buildAudioReadingOrder(
  items: SyncNarrationItem[],
  publication: ReadiumPublication
): Link[] {
  const seen = new Map<
    string,
    { cueSum: number; declaredDuration?: number; title?: string }
  >();

  for (const item of items) {
    const key = item.audioHref;
    if (!seen.has(key)) {
      seen.set(key, { cueSum: 0 });
    }
    const entry = seen.get(key)!;
    if (item.audioStart !== null && item.audioEnd !== null) {
      entry.cueSum += item.audioEnd - item.audioStart;
    }
    if (item.readingOrderDuration !== undefined) {
      entry.declaredDuration = Math.max(
        entry.declaredDuration ?? 0,
        item.readingOrderDuration
      );
    }
    if (!entry.title && item.tocTitle) {
      entry.title = item.tocTitle;
    }
  }

  // Absolutize the self link against the document origin before deriving the
  // base URL. If the manifest's self link is relative/root-relative (e.g. a
  // publication served at "/test-overlay/manifest.json"), a non-absolute base
  // produces non-absolute audio hrefs, which the upstream AudioNavigator then
  // resolves a *second* time against the publication base — doubling the
  // sub-path (".../test-overlay/test-overlay/01.mp3" → 404). Fully-qualifying
  // here makes the synthetic hrefs absolute so upstream leaves them untouched.
  // Already-absolute self links (e.g. remote "https://…/manifest.json") are
  // returned unchanged by `new URL`.
  const rawSelfHref = publication.manifest.linksWithRel("self")[0]?.href ?? "";
  const selfHref =
    rawSelfHref && typeof window !== "undefined"
      ? new URL(rawSelfHref, window.location.href).href
      : rawSelfHref;
  const baseUrl = selfHref.endsWith("/")
    ? selfHref
    : selfHref.slice(0, selfHref.lastIndexOf("/") + 1);

  return Array.from(seen.entries()).map(([href, meta]) => {
    const absoluteHref = href.startsWith("http") ? href : baseUrl + href;
    const duration =
      meta.declaredDuration ?? (meta.cueSum > 0 ? meta.cueSum : undefined);
    return new Link({
      href: absoluteHref,
      type: _audioMimeType(href),
      title: meta.title,
      duration,
    });
  });
}

function _audioMimeType(href: string): string {
  if (href.endsWith(".mp3")) return "audio/mpeg";
  if (href.endsWith(".ogg") || href.endsWith(".oga")) return "audio/ogg";
  if (href.endsWith(".opus")) return "audio/ogg; codecs=opus";
  if (href.endsWith(".m4a") || href.endsWith(".aac")) return "audio/mp4";
  if (href.endsWith(".wav")) return "audio/wav";
  return "audio/mpeg"; // reasonable default
}

/**
 * Wraps the original publication's manifest into a minimal Publication that
 * conforms to the Audiobook profile, using the synthetic reading order.
 */
function _buildAudiobookPublication(
  publication: ReadiumPublication,
  audioReadingOrder: Link[]
): ReadiumPublication {
  const manifestJson = publication.manifest.serialize();
  manifestJson.readingOrder = audioReadingOrder.map((l) => l.serialize());
  if (!manifestJson.metadata) manifestJson.metadata = {};
  manifestJson.metadata.conformsTo = [Profile.AUDIOBOOK];

  const manifest = Manifest.deserialize(manifestJson);
  if (!manifest) {
    throw new Error("Failed to create new Audiobook manifest");
  }

  const selfLink = publication.manifest.linksWithRel("self")[0];
  if (selfLink?.href) manifest.setSelfLink(selfLink.href);

  return new ReadiumPublication({ manifest, fetcher: (publication as any).fetcher });
}

// ---------------------------------------------------------------------------
// Test-only exports
//
// The double-underscore prefix marks these as internal — not part of the
// module's public API, only exposed for unit tests in __tests__/.
// ---------------------------------------------------------------------------

export const __testing__ = {
  audioMimeType: _audioMimeType,
  resolveItemHrefs: _resolveItemHrefs,
  buildAudioReadingOrder: _buildAudioReadingOrder,
};
