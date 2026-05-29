/**
 * Sync Narration (Media Overlay) parser for the web platform.
 *
 * Mirrors FlutterMediaOverlay / FlutterMediaOverlayItem in the Swift and Kotlin
 * plugin layers.  Reads the Readium "Sync Narration JSON" format embedded in EPUB
 * reading-order alternates and produces a flat list of SyncNarrationItem entries
 * that can be used to:
 *  - build a synthetic audio reading order for AudioNavigator, and
 *  - map AudioNavigator position events back to text locators.
 *
 * Sync Narration JSON format:
 *   { "narration": [{ "audio": "chap.mp3#t=0,3.5", "text": "chap.html#par001" }, ...] }
 *
 * The media type for a narration alternate is typically:
 *   application/vnd.readium.narration+json
 */

import { Link, Locator, LocatorLocations, Resource } from "@readium/shared";
import { ReadiumPublication } from "../extensions/ReadiumPublication";
import { createLogger } from "../logger";

const log = createLogger("SyncNarration");

/** MIME type used by Readium to identify Sync Narration JSON alternates. */
const NARRATION_MEDIA_TYPE = "application/vnd.readium.narration+json";

export interface SyncNarrationItem {
  /** Original "audio" field, e.g. "chapter1.mp3#t=12.34,15.67" */
  audio: string;
  /** Original "text" field, e.g. "chapter1.html#p001" */
  text: string;
  /** Index of the parent reading-order link (for ordering). */
  position: number;
  /** Resolved audio file href (without fragment). */
  audioHref: string;
  audioStart: number | null;
  audioEnd: number | null;
  /** Resolved text file href (without fragment). */
  textHref: string;
  /** Text element ID (the fragment after '#' in the text field). */
  textId: string;
  tocTitle?: string;
  tocHref?: string;
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/**
 * Returns true if the publication has at least one reading-order link with a
 * Sync Narration JSON alternate.
 */
export function detectSyncNarration(publication: ReadiumPublication): boolean {
  for (const link of publication.readingOrder.items) {
    if (_narrationAlternate(link) !== null) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/**
 * Fetches and parses all Sync Narration JSON alternates in the publication's
 * reading order.  Returns a flat, position-ordered list of SyncNarrationItem.
 */
export async function parseSyncNarration(
  publication: ReadiumPublication
): Promise<SyncNarrationItem[]> {
  const result: SyncNarrationItem[] = [];

  for (let i = 0; i < publication.readingOrder.items.length; i++) {
    const link = publication.readingOrder.items[i];
    const narrationLink = _narrationAlternate(link);
    if (!narrationLink) continue;

    try {
      const resource: Resource = publication.get(narrationLink);
      const json = await resource.readAsJSON();
      const items = _parseNarrationJson(json, i);
      result.push(...items);
    } catch (err) {
      log.warn("Failed to fetch/parse alternate for", link.href, err);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Locator helpers
// ---------------------------------------------------------------------------

/**
 * Builds a text-based Locator for a SyncNarrationItem.
 * Mirrors FlutterMediaOverlayItem.asTextLocator in the Swift plugin.
 */
export function textLocatorForItem(item: SyncNarrationItem): Locator {
  const otherLocations: Map<string, any> | undefined = item.textId
    ? new Map<string, any>([["cssSelector", `#${item.textId}`]])
    : undefined;
  return new Locator({
    href: item.textHref,
    type: "text/html",
    locations: new LocatorLocations({
      fragments: item.textId ? [item.textId] : [],
      otherLocations,
    }),
    title: item.tocTitle,
  });
}

/**
 * Merges a text locator with audio progression data from an AudioNavigator
 * position locator.
 * Mirrors FlutterMediaOverlayItem.toCombinedLocator in the Swift plugin.
 */
export function combinedLocatorForItem(
  item: SyncNarrationItem,
  audioLocator: Locator
): Locator {
  const textLoc = textLocatorForItem(item);
  const otherLocations: Map<string, any> | undefined = item.textId
    ? new Map<string, any>([["cssSelector", `#${item.textId}`]])
    : undefined;
  return new Locator({
    href: textLoc.href,
    type: textLoc.type,
    title: textLoc.title,
    locations: new LocatorLocations({
      fragments: textLoc.locations?.fragments ?? [],
      progression: audioLocator.locations?.progression,
      totalProgression: audioLocator.locations?.totalProgression,
      otherLocations,
    }),
    text: audioLocator.text,
  });
}

/**
 * Maps a text-based Locator to an audio Locator by finding the matching
 * SyncNarrationItem, then computing a time offset using (in priority order):
 *  1. A `t=<n>` fragment already present in the text locator.
 *  2. `progression × (audioEnd − audioStart)` offset within the item.
 *  3. Fallback to item.audioStart.
 *
 * Returns undefined when no matching item is found.
 *
 * Mirrors FlutterMediaOverlayNavigator.mapTextLocatorToMediaOverlayAudioLocator
 * (iOS) and SyncAudiobookNavigator.mapTextLocatorToMediaOverlayLocator (Android).
 */
export function textLocatorToAudioLocator(
  items: SyncNarrationItem[],
  textLocator: Locator
): Locator | undefined {
  log.debug("Mapping text locator to audio locator:", textLocator.href);
  log.debug("Available SyncNarrationItems:");
  for (const item of items) {
    log.debug(`- textHref: ${item.textHref}, textId: ${item.textId}, audioHref: ${item.audioHref}, audioStart: ${item.audioStart}, audioEnd: ${item.audioEnd}`);
  }
  const targetHref = textLocator.href;
  const targetId =
    (textLocator.locations as any)?.fragments?.[0] ??
    // cssSelector lives in otherLocations (a Map) — JSON.stringify would drop it,
    // so we access it via Map.get rather than as a direct property.
    textLocator.locations?.otherLocations?.get?.("cssSelector")?.replace(/^#/, "") ??
    "";

  const match = items.find(
    (item) =>
      _normalizeHref(item.textHref) === _normalizeHref(targetHref) &&
      (!targetId || item.textId === targetId)
  );

  if (!match || match.audioStart === null) return undefined;

  // Priority 1: t= fragment already in the incoming locator.
  const tFragment = (textLocator.locations as any)?.fragments?.find(
    (f: string) => f.startsWith("t=")
  );
  let timeOffset: number = match.audioStart;
  if (tFragment) {
    const parsed = parseFloat(tFragment.slice(2));
    if (!isNaN(parsed)) timeOffset = parsed;
  } else if (
    textLocator.locations?.progression != null &&
    match.audioEnd !== null
  ) {
    // Priority 2: progression within the item range.
    timeOffset =
      match.audioStart +
      textLocator.locations.progression * (match.audioEnd - match.audioStart);
  }
  // Priority 3: fallback to audioStart (already set as default above).

  return new Locator({
    href: match.audioHref,
    type: "audio/mpeg",
    locations: new LocatorLocations({
      fragments: [`t=${timeOffset}`],
    }),
  });
}

/**
 * Finds the SyncNarrationItem that covers a given audio position.
 * Mirrors FlutterMediaOverlay.itemInRangeOfTime.
 *
 * @param items   All parsed items (ordered by position).
 * @param audioHref  The href of the currently-playing audio file.
 * @param timeSecs   Current playback time in seconds.
 */
export function findItemByAudioTime(
  items: SyncNarrationItem[],
  audioHref: string,
  timeSecs: number
): SyncNarrationItem | undefined {
  // Normalise hrefs for comparison (strip leading slash / URL prefix if any).
  const normHref = _normalizeHref(audioHref);

  for (const item of items) {
    if (_normalizeHref(item.audioHref) !== normHref) continue;
    const start = item.audioStart ?? 0;
    const end = item.audioEnd;
    if (timeSecs >= start && (end === null || timeSecs <= end)) {
      return item;
    }
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function _narrationAlternate(link: Link): Link | null {
  // `alternates` is a `Links` instance (not a plain array): use `.items` for
  // iteration and `findWithMediaType` for the typed lookup.
  const alternates = link.alternates;
  if (!alternates) return null;
  const byType = alternates.findWithMediaType(NARRATION_MEDIA_TYPE);
  if (byType) return byType;
  return alternates.items.find((alt) => alt.href.endsWith(".json")) ?? null;
}

/** Recursively parse { narration: [{audio, text}, ...] } entries. */
function _parseNarrationJson(
  json: any,
  position: number
): SyncNarrationItem[] {
  const items: SyncNarrationItem[] = [];

  if (!json || !Array.isArray(json.narration)) return items;

  for (const entry of json.narration) {
    if (entry && typeof entry.audio === "string" && typeof entry.text === "string") {
      items.push(_parseEntry(entry, position));
    } else if (entry && Array.isArray(entry.narration)) {
      // Nested narration (body element groups in some authoring tools).
      items.push(..._parseNarrationJson(entry, position));
    }
  }

  return items;
}

function _parseEntry(entry: { audio: string; text: string }, position: number): SyncNarrationItem {
  const { audioHref, audioStart, audioEnd } = _parseAudioField(entry.audio);
  const { textHref, textId } = _parseTextField(entry.text);

  return {
    audio: entry.audio,
    text: entry.text,
    position,
    audioHref,
    audioStart,
    audioEnd,
    textHref,
    textId,
  };
}

/** Parses "chapter.mp3#t=12.34,15.67" into its components. */
function _parseAudioField(audio: string): {
  audioHref: string;
  audioStart: number | null;
  audioEnd: number | null;
} {
  const hashIdx = audio.indexOf("#");
  if (hashIdx === -1) {
    return { audioHref: audio, audioStart: null, audioEnd: null };
  }

  const audioHref = audio.slice(0, hashIdx);
  const fragment = audio.slice(hashIdx + 1); // "t=12.34,15.67"

  let audioStart: number | null = null;
  let audioEnd: number | null = null;

  const match = fragment.match(/^t=([^,]+)(?:,(.+))?$/);
  if (match) {
    const s = parseFloat(match[1]);
    audioStart = isNaN(s) ? null : s;
    const e = match[2] ? parseFloat(match[2]) : NaN;
    audioEnd = isNaN(e) ? null : e;
  }

  return { audioHref, audioStart, audioEnd };
}

/** Parses "chapter.html#p001" into href and fragment id. */
function _parseTextField(text: string): { textHref: string; textId: string } {
  const hashIdx = text.indexOf("#");
  if (hashIdx === -1) {
    return { textHref: text, textId: "" };
  }
  return {
    textHref: text.slice(0, hashIdx),
    textId: text.slice(hashIdx + 1),
  };
}

export function _normalizeHref(href: string): string {
  // Strip leading slash and query/fragment for comparison purposes.
  return href.replace(/^\//, "").split("?")[0].split("#")[0];
}
