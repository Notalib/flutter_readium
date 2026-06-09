/**
 * Shared TOC-href enrichment helpers used by all three playback paths
 * (EPUB visual, TTS, audiobook, and media overlay).
 *
 * Consolidates logic previously duplicated between epubNavigator.ts and the
 * publication-based flattenToc in syncNarration.ts.
 */

import { Link, Locator, LocatorLocations } from "@readium/shared";

// ---------------------------------------------------------------------------
// TOC flattening
// ---------------------------------------------------------------------------

/**
 * Recursively walk a `Link[]` tree and return a flat list of every entry.
 * Callers that have a `ReadiumPublication` should pass
 * `publication.manifest.toc?.items ?? []`.
 */
export function flattenToc(items: readonly Link[]): Link[] {
  const out: Link[] = [];
  for (const link of items) {
    out.push(link);
    const children = link.children?.items;
    if (children && children.length > 0) {
      out.push(...flattenToc(children));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Href-based enrichment (EPUB / TTS)
// ---------------------------------------------------------------------------

/**
 * Adds `tocHref` to `locator.locations.otherLocations` by matching the
 * locator's resource href against the flat ToC link list.
 *
 * - Does NOT clobber an existing `tocHref` entry.
 * - Returns the original locator unchanged when `flatToc` is empty or no match
 *   is found.
 * - Preserves all existing `locations` fields (fragments, progression, position,
 *   totalProgression, otherLocations).
 *
 * Moved from epubNavigator.ts; the logic there is unchanged.
 */
export function enrichLocatorWithTocHref(
  locator: Locator,
  flatToc: Link[]
): Locator {
  if (flatToc.length === 0) return locator;
  const tocHref = _findCurrentTocHref(locator.href, flatToc);
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

// ---------------------------------------------------------------------------
// Time-based enrichment (audiobook)
// ---------------------------------------------------------------------------

/**
 * Returns the `tocHref` for an audio locator using time-fragment-aware
 * matching — mirroring `currentTocLinkFromTimeLocator` in
 * FlutterReadiumPlugin.swift (iOS).
 *
 * Strategy (mirrors iOS):
 *  1. Filter the flat ToC to entries whose resource path matches the locator's
 *     resource path (strip fragments from both).
 *  2. Walk those entries in document order. For each entry, parse its `#t=`
 *     begin time; skip entries without a time fragment.
 *  3. Keep updating `matched` as long as the entry's begin time is ≤ current
 *     time; stop once a begin time exceeds the current time.
 *  4. Return `matched?.href` (the full href including its `#t=` fragment) or
 *     `undefined`.
 *
 * Current time is read from `locator.locations?.time?.()` when available
 * (the accessor name in @readium/shared LocatorLocations); otherwise the
 * locator's own `#t=<n>` fragment is parsed.
 *
 * Returns `undefined` when `flatToc` is empty, no resource path match is
 * found, or no entry has a time fragment ≤ current time.
 */
export function tocHrefForTimeLocator(
  locator: Locator,
  flatToc: Link[]
): string | undefined {
  if (flatToc.length === 0) return undefined;

  const resourcePath = _stripFragment(locator.href);

  // Current playback time in seconds.
  let currentTime: number | undefined = locator.locations?.time?.();
  if (currentTime === undefined) {
    // Parse from the locator's own t= fragment.
    const tFrag = locator.locations?.fragments?.find((f: string) =>
      f.startsWith("t=")
    );
    if (tFrag) {
      const parsed = parseFloat(tFrag.slice(2).split(",")[0]);
      if (!isNaN(parsed)) currentTime = parsed;
    }
  }

  // Entries that share this audio file.
  const matching = flatToc.filter(
    (l) => _stripFragment(l.href) === resourcePath
  );
  if (matching.length === 0) return undefined;

  let matched: Link | undefined;
  for (const tocLink of matching) {
    const beginTime = _parseTimeFragmentBegin(tocLink.href);
    if (beginTime === undefined) continue;
    if (currentTime !== undefined && beginTime > currentTime) break;
    matched = tocLink;
  }
  return matched?.href;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

function _findCurrentTocHref(
  resourceHref: string,
  flatToc: Link[]
): string | undefined {
  const targetPath = _stripFragment(resourceHref);
  const match = flatToc.find((l) => _stripFragment(l.href) === targetPath);
  return match?.href;
}

function _stripFragment(href: string): string {
  const i = href.indexOf("#");
  return i === -1 ? href : href.substring(0, i);
}

/**
 * Parses `#t=<begin>[,<end>]` from an href and returns `begin` as a number,
 * or `undefined` when the fragment is absent or unparseable.
 */
function _parseTimeFragmentBegin(href: string): number | undefined {
  const hashIdx = href.indexOf("#");
  if (hashIdx === -1) return undefined;
  const fragment = href.slice(hashIdx + 1); // e.g. "t=12.34,15.67"
  const match = fragment.match(/^t=([^,]+)/);
  if (!match) return undefined;
  const n = parseFloat(match[1]);
  return isNaN(n) ? undefined : n;
}
