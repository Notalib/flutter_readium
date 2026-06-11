import { Profile, Publication, MediaType, Link } from "@readium/shared";

export class ReadiumPublication extends Publication {
  /** All resource links from readingOrder + resources, flattened into a single array. */
  get allLinks(): Link[] {
    return [
      ...this.readingOrder.items,
      ...(this.resources?.items ?? []),
    ];
  }

  private conformsToArray = this.manifest.metadata.conformsTo;

  public conformsToEpub: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.EPUB;
    }) ?? false;

  public conformsToAudiobook: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.AUDIOBOOK;
    }) ?? false;

  public conformsToDivina: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.DIVINA;
    }) ?? false;

  public conformsToPDF: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.PDF;
    }) ?? false;
}

/** Finds a link by href, falling back to pathname comparison for relative vs. absolute mismatches. */
export function findLinkByHref(
  items: Link[] | undefined,
  href: string
): Link | undefined {
  if (!items || items.length === 0) return undefined;
  const exact = items.find((l) => l.href === href);
  if (exact) return exact;
  try {
    const hrefPath = new URL(href, "http://localhost").pathname;
    return items.find((l) => {
      try {
        return new URL(l.href, "http://localhost").pathname === hrefPath;
      } catch {
        return false;
      }
    });
  } catch {
    return undefined;
  }
}

export function mediaTypes(publication: ReadiumPublication): MediaType[] {
  return publication.manifest.linksWithRel("self")
    .map((link) => link.type)
    .filter((type): type is string => typeof type === "string")
    .map((type) => MediaType.parse({ mediaType: type }));
}
