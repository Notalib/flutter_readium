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
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { createLogger } from "../logger";
import { AudioLocatorMapper, initializeAudioNavigator } from "./audioNavigator";
import {
  SyncNarrationItem,
  combinedLocatorForItem,
  findItemByAudioTime,
  parseSyncNarration,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "./syncNarration";
import { parseGuidedNavigation } from "./guidedNavigation";

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
 */
export async function initializeMediaOverlayNavigator(
  publication: ReadiumPublication,
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: (nav: AudioNavigator, items: SyncNarrationItem[]) => void,
  onTextLocatorChanged?: (locator: Locator) => void
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
  onTextLocatorChanged?: (locator: Locator) => void
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
  onTextLocatorChanged: ((locator: Locator) => void) | undefined,
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

  const audioInitialLocator = initialLocator
    ? textLocatorToAudioLocator(items, initialLocator)
    : undefined;
  if (initialLocator) {
    log.info(
      audioInitialLocator
        ? `Initial text locator mapped to audio ${audioInitialLocator.href} ${audioInitialLocator.locations?.fragments?.[0] ?? ""}`
        : `Initial text locator could not be mapped to an audio item — starting at beginning`
    );
  }

  const mapper: AudioLocatorMapper = (nav, audioLocator) => {
    const item = findItemByAudioTime(items, audioLocator.href, nav.currentTime);
    if (item) {
      return {
        stateLocator: combinedLocatorForItem(item, audioLocator),
        textLocator: textLocatorForItem(item),
      };
    }
    return { stateLocator: audioLocator };
  };

  await initializeAudioNavigator(
    syntheticPub,
    audioInitialLocator,
    prefsJson,
    (nav) => setNav(nav, items),
    mapper,
    onTextLocatorChanged
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

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

  const selfHref = publication.manifest.linksWithRel("self")[0]?.href ?? "";
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

  const manifest = Manifest.deserialize(manifestJson)!;
  if (manifest == undefined) {
    throw new Error("Failed to create new Audiobook manifest");
  }

  const selfLink = publication.manifest.linksWithRel("self")[0];
  if (selfLink?.href) manifest.setSelfLink(selfLink.href);

  return new ReadiumPublication({ manifest, fetcher: (publication as any).fetcher });
}
