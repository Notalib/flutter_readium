/**
 * Guided Navigation parser for the web platform.
 *
 * Mirrors the iOS `getGuidedNavigationMediaOverlays()` and Android equivalent.
 * Reads the Readium "Guided Navigation JSON" format and produces a flat list of
 * SyncNarrationItem entries — the same shape used by syncNarration.ts — so that
 * the downstream mediaOverlayNavigator.ts can consume both formats uniformly.
 *
 * Guided Navigation JSON format:
 *   { "guided": [{ "audioref": "chap.mp3#t=0,3.5", "textref": "chap.html#par001", "children": [] }, ...] }
 *
 * Detection strategies (mirrors iOS ReadiumExtensions.swift):
 *   Strategy 1 (preferred): single document in publication.manifest.links
 *   Strategy 2 (fallback):  per-reading-order alternates
 */

import { Link, Resource } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import {
  SyncNarrationItem,
  enrichItemsWithToc,
  isJsonObject,
  parseAudioField,
  parseImgField,
  parseTextField,
  normalizeHref,
} from "./syncNarration";

const log = createLogger("GuidedNavigation");

export const GUIDED_NAVIGATION_MEDIA_TYPE = "application/guided-navigation+json";

// ---------------------------------------------------------------------------
// Minimal internal types
// ---------------------------------------------------------------------------

interface GuidedNavigationObject {
  audioref?: string;
  textref?: string;
  imgref?: string;
  children: GuidedNavigationObject[];
}

interface GuidedNavigationDocument {
  guided: GuidedNavigationObject[];
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/**
 * Returns true if the publication declares Guided Navigation either as a
 * publication-level link or as an alternate on any reading-order link.
 *
 * Note the asymmetry with `detectSyncNarration`, which only inspects
 * reading-order alternates: Sync Narration is always authored per-chapter, but
 * Guided Navigation can also live at the publication level as a single
 * document covering the whole book. We have to check both surfaces.
 */
export function detectGuidedNavigation(publication: ReadiumPublication): boolean {
  if (_publicationLevelLink(publication)) return true;
  for (const link of publication.readingOrder.items) {
    const alternates = link.alternates;
    if (!alternates) continue;
    if (alternates.findWithMediaType(GUIDED_NAVIGATION_MEDIA_TYPE)) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/**
 * Fetches and parses the Guided Navigation JSON(s) and returns a flat list of
 * SyncNarrationItem. Strategy 1 (publication-level link) is preferred;
 * Strategy 2 (per-reading-order alternates) is the fallback.
 */
export async function parseGuidedNavigation(
  publication: ReadiumPublication
): Promise<SyncNarrationItem[]> {
  const singleDocLink = _publicationLevelLink(publication);
  const items = singleDocLink
    ? await _parsePublicationLevelDocument(publication, singleDocLink)
    : await _parseReadingOrderAlternates(publication);
  return enrichItemsWithToc(items, publication);
}

// ---------------------------------------------------------------------------
// Strategy implementations
//
// Two strategies, matching the iOS getGuidedNavigationMediaOverlays():
//   Strategy 1: a single publication-level guided-navigation document.
//   Strategy 2: per-reading-order alternates (fallback).
//
// Error-handling asymmetry between the two is intentional and matches iOS:
//   Strategy 1 fails entirely on the first error (one document = all or nothing).
//   Strategy 2 logs and continues to the next alternate (one bad chapter shouldn't
//   wipe out playback for the rest of the book).
// ---------------------------------------------------------------------------

async function _parsePublicationLevelDocument(
  publication: ReadiumPublication,
  link: Link
): Promise<SyncNarrationItem[]> {
  let document: GuidedNavigationDocument | null = null;
  try {
    const resource: Resource = publication.get(link);
    const json = await resource.readAsJSON();
    document = _parseDocument(json);
  } catch (err) {
    log.warn("Strategy 1: failed to fetch/parse guided navigation document", err);
    return [];
  }

  if (!document) {
    log.warn("Strategy 1: guided navigation document had no usable 'guided' entries");
    return [];
  }

  const items: SyncNarrationItem[] = [];
  for (const obj of document.guided) {
    _flattenWithReadingOrderLookup(obj, items, publication);
  }
  return items;
}

async function _parseReadingOrderAlternates(
  publication: ReadiumPublication
): Promise<SyncNarrationItem[]> {
  const result: SyncNarrationItem[] = [];

  for (let i = 0; i < publication.readingOrder.items.length; i++) {
    const roLink = publication.readingOrder.items[i];
    const alternates = roLink.alternates;
    if (!alternates) continue;
    const gnLink = alternates.findWithMediaType(GUIDED_NAVIGATION_MEDIA_TYPE);
    if (!gnLink) continue;

    let document: GuidedNavigationDocument | null = null;
    try {
      const resource: Resource = publication.get(gnLink);
      const json = await resource.readAsJSON();
      document = _parseDocument(json);
    } catch (err) {
      log.warn("Strategy 2: failed to fetch/parse alternate for", roLink.href, err);
      continue;
    }

    if (!document) {
      log.warn("Strategy 2: alternate had no usable 'guided' entries for", roLink.href);
      continue;
    }

    const position = i + 1;
    const readingOrderDuration = roLink.duration;
    for (const obj of document.guided) {
      _flattenWithFixedPosition(obj, position, readingOrderDuration, result);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Flatten helpers
// ---------------------------------------------------------------------------

/**
 * Strategy 1 flatten: position is derived per item by matching the textref's
 * file path against the publication's reading order — 1-based index when
 * matched, 0 when unmatched. The matched reading-order link's `duration`
 * (when declared) is attached to the item as `readingOrderDuration`.
 * Mirrors iOS: `(roEntry?.offset ?? -1) + 1` and `roEntry?.element.duration`.
 */
function _flattenWithReadingOrderLookup(
  obj: GuidedNavigationObject,
  out: SyncNarrationItem[],
  publication: ReadiumPublication
): void {
  if (obj.audioref !== undefined && obj.textref !== undefined) {
    const { textHref } = parseTextField(obj.textref);
    const roIndex = publication.readingOrder.items.findIndex(
      (link: Link) => normalizeHref(link.href) === normalizeHref(textHref)
    );
    const position = roIndex === -1 ? 0 : roIndex + 1;
    const readingOrderDuration =
      roIndex === -1 ? undefined : publication.readingOrder.items[roIndex].duration;
    out.push(_buildItem(obj.audioref, obj.textref, obj.imgref, position, readingOrderDuration));
  }
  for (const child of obj.children) {
    _flattenWithReadingOrderLookup(child, out, publication);
  }
}

/**
 * Strategy 2 flatten: position is fixed (readingOrderIndex + 1) for every item
 * in this document, because the document is itself attached to that reading-order
 * entry. The reading-order entry's duration is propagated to every item.
 */
function _flattenWithFixedPosition(
  obj: GuidedNavigationObject,
  position: number,
  readingOrderDuration: number | undefined,
  out: SyncNarrationItem[]
): void {
  if (obj.audioref !== undefined && obj.textref !== undefined) {
    out.push(_buildItem(obj.audioref, obj.textref, obj.imgref, position, readingOrderDuration));
  }
  for (const child of obj.children) {
    _flattenWithFixedPosition(child, position, readingOrderDuration, out);
  }
}

function _buildItem(
  audioref: string,
  textref: string,
  imgref: string | undefined,
  position: number,
  readingOrderDuration: number | undefined
): SyncNarrationItem {
  const { audioHref, audioStart, audioEnd } = parseAudioField(audioref);
  const { textHref, textId } = parseTextField(textref);
  // Panel region (xywh) comes from imgref, not textref. Absent → page-level cue.
  const region = imgref !== undefined ? parseImgField(imgref).region : null;
  return {
    audio: audioref,
    text: textref,
    position,
    audioHref,
    audioStart,
    audioEnd,
    textHref,
    textId,
    readingOrderDuration,
    region: region ?? undefined,
  };
}

// ---------------------------------------------------------------------------
// JSON parsing
// ---------------------------------------------------------------------------

function _parseDocument(json: unknown): GuidedNavigationDocument | null {
  if (!isJsonObject(json)) return null;
  const guidedRaw = json["guided"];
  if (!Array.isArray(guidedRaw) || guidedRaw.length === 0) return null;

  const guided: GuidedNavigationObject[] = [];
  for (const item of guidedRaw) {
    const parsed = _parseObject(item);
    if (parsed) guided.push(parsed);
  }

  if (guided.length === 0) return null;
  return { guided };
}

function _parseObject(json: unknown): GuidedNavigationObject | null {
  if (!isJsonObject(json)) return null;

  const audiorefRaw = json["audioref"];
  const textrefRaw = json["textref"];
  const imgrefRaw = json["imgref"];
  const audioref = typeof audiorefRaw === "string" ? audiorefRaw : undefined;
  const textref = typeof textrefRaw === "string" ? textrefRaw : undefined;
  const imgref = typeof imgrefRaw === "string" ? imgrefRaw : undefined;

  const children: GuidedNavigationObject[] = [];
  const childrenRaw = json["children"];
  if (Array.isArray(childrenRaw)) {
    for (const childJson of childrenRaw) {
      const parsedChild = _parseObject(childJson);
      if (parsedChild) children.push(parsedChild);
    }
  }

  if (audioref === undefined && textref === undefined && children.length === 0) return null;
  return { audioref, textref, imgref, children };
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function _publicationLevelLink(
  publication: ReadiumPublication
): Link | undefined {
  const links = publication.manifest.links;
  if (!links) return undefined;
  return links.findWithMediaType(GUIDED_NAVIGATION_MEDIA_TYPE);
}

// ---------------------------------------------------------------------------
// Test-only exports
//
// The double-underscore prefix marks these as internal — not part of the
// module's public API, only exposed for unit tests in __tests__/.
// ---------------------------------------------------------------------------

export const __testing__ = {
  parseDocument: _parseDocument,
  parseObject: _parseObject,
};
