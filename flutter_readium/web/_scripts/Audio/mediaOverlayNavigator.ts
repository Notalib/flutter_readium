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

import { Link, Locator, LocatorLocations, Manifest, Profile } from "@readium/shared";
import { AudioNavigator } from "@readium/navigator";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { AudioLocatorMapper, initializeAudioNavigator } from "./audioNavigator";
import {
  SyncNarrationItem,
  _normalizeHref,
  combinedLocatorForItem,
  findItemByAudioTime,
  parseSyncNarration,
  textLocatorForItem,
} from "./syncNarration";

/**
 * Initialises a Media Overlay session for the given EPUB publication.
 *
 * @param publication     The EPUB publication (must have Sync Narration alternates).
 * @param initialLocator  Optional starting text locator (will be mapped to audio time).
 * @param prefsJson       Dart AudioPreferences JSON string.
 * @param setNav          Callback invoked once AudioNavigator is ready.
 */
export async function initializeMediaOverlayNavigator(
  publication: ReadiumPublication,
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: (nav: AudioNavigator) => void
): Promise<void> {
  console.log("Initializing MediaOverlayNavigator");

  const items = await parseSyncNarration(publication);
  if (items.length === 0) {
    console.warn("MediaOverlay: no sync narration items found; aborting.");
    return;
  }

  // Build synthetic audio reading order: one Link per unique audio file,
  // preserving reading-order position.
  const audioReadingOrder = _buildAudioReadingOrder(items, publication);

  // Build a synthetic Publication with the audiobook profile and audio reading order.
  const syntheticPub = _buildAudiobookPublication(publication, audioReadingOrder);

  // Map initial text locator -> audio locator.
  const audioInitialLocator = initialLocator
    ? _textLocatorToAudioLocator(items, initialLocator)
    : undefined;

  // Locator mapper: applied by every state-emitting listener (play, pause,
  // positionChanged, trackEnded, error, stalled) so ALL state transitions
  // carry text-based locators, not raw audio-file hrefs.
  const mapper: AudioLocatorMapper = (nav, audioLocator) => {
    const item = findItemByAudioTime(items, audioLocator.href, nav.currentTime);
    if (item) {
      return {
        stateLocator: combinedLocatorForItem(item, audioLocator),
        textLocator: textLocatorForItem(item),
      };
    }
    // No item matched (e.g. gap between cues) — fall back to raw audio locator.
    return { stateLocator: audioLocator };
  };

  await initializeAudioNavigator(
    syntheticPub,
    audioInitialLocator,
    prefsJson,
    setNav,
    mapper
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/**
 * One Link per unique audio file, ordered by first appearance in reading order.
 * Duration is the sum of (audioEnd - audioStart) for items in that file.
 */
function _buildAudioReadingOrder(
  items: SyncNarrationItem[],
  publication: ReadiumPublication
): Link[] {
  const seen = new Map<string, { duration: number; title?: string }>();

  for (const item of items) {
    const key = item.audioHref;
    if (!seen.has(key)) {
      seen.set(key, { duration: 0 });
    }
    const entry = seen.get(key)!;
    if (item.audioStart !== null && item.audioEnd !== null) {
      entry.duration += item.audioEnd - item.audioStart;
    }
    if (!entry.title && item.tocTitle) {
      entry.title = item.tocTitle;
    }
  }

  // Resolve absolute hrefs using the publication's self-link base URL.
  const selfHref = publication.manifest.linksWithRel("self")[0]?.href ?? "";
  const baseUrl = selfHref.endsWith("/")
    ? selfHref
    : selfHref.slice(0, selfHref.lastIndexOf("/") + 1);

  return Array.from(seen.entries()).map(([href, meta]) => {
    // href may be relative; resolve against the publication base.
    const absoluteHref = href.startsWith("http") ? href : baseUrl + href;
    return new Link({
      href: absoluteHref,
      type: _audioMimeType(href),
      title: meta.title,
      duration: meta.duration > 0 ? meta.duration : undefined,
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
  // Serialise manifest, swap out readingOrder, update conformsTo.
  const manifestJson = JSON.parse(JSON.stringify(publication.manifest));
  manifestJson.readingOrder = audioReadingOrder.map((l) => JSON.parse(JSON.stringify(l)));
  if (!manifestJson.metadata) manifestJson.metadata = {};
  manifestJson.metadata.conformsTo = [Profile.AUDIOBOOK];

  const manifest = Manifest.deserialize(manifestJson)!;
  if (manifest == undefined) {
    throw new Error("Failed to create new Audiobook manifest");
  }

  // Preserve the self-link so the fetcher base URL remains correct.
  const selfLink = publication.manifest.linksWithRel("self")[0];
  if (selfLink?.href) manifest.setSelfLink(selfLink.href);

  return new ReadiumPublication({ manifest, fetcher: (publication as any).fetcher });
}

/**
 * Maps a text-based starting locator to an audio locator by finding the first
 * SyncNarrationItem whose textHref/textId matches the requested href/fragment.
 */
function _textLocatorToAudioLocator(
  items: SyncNarrationItem[],
  textLocator: Locator
): Locator | undefined {
  const targetHref = textLocator.href;
  const targetId =
    (textLocator.locations as any)?.fragments?.[0] ??
    (textLocator.locations as any)?.cssSelector?.replace(/^#/, "") ??
    "";

  const match = items.find(
    (item) =>
      _normalizeHref(item.textHref) === _normalizeHref(targetHref) &&
      (!targetId || item.textId === targetId)
  );

  if (!match || match.audioStart === null) return undefined;

  return new Locator({
    href: match.audioHref,
    type: "audio/mpeg",
    locations: new LocatorLocations({
      fragments: [`t=${match.audioStart}`],
    }),
  });
}
