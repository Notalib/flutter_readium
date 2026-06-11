import { Locator, LocatorLocations, Link } from "@readium/shared";

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

/**
 * Walks the `toc` link tree and returns a flat list of every entry.
 */
export function flattenToc(items: Link[]): Link[] {
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

/**
 * Adds `tocHref` to `locator.locations.otherLocations` so the Dart-side
 * `Locator.locations.tocHref` getter returns the current chapter's TOC href.
 *
 * Matches by resource href (strips any `#fragment`). If the publication's TOC
 * has multiple entries pointing into the same resource, the first one wins.
 */
export function enrichWithTocHref(locator: Locator, flatTocItems: Link[]): Locator {
  if (flatTocItems.length === 0) return locator;
  const tocHref = findCurrentTocHref(locator.href, flatTocItems);
  if (!tocHref) return locator;
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
  flatTocItems: Link[]
): string | undefined {
  const targetPath = stripFragment(resourceHref);
  const match = flatTocItems.find((l) => stripFragment(l.href) === targetPath);
  return match?.href;
}

function stripFragment(href: string): string {
  const i = href.indexOf("#");
  return i === -1 ? href : href.substring(0, i);
}
