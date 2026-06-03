/**
 * PublicationManager — publication lifecycle and manifest cache.
 *
 * Manages a shared in-memory cache of fetched publications (keyed by
 * publication identifier). The static cache mirrors the original
 * singleton behaviour so all instances share the same pool.
 */

import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { fetchManifest } from "../utils/manifest";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("PubManager");

export class PublicationManager {
  /** Cross-instance publication cache keyed by publication identifier. */
  private static readonly _cache: Map<string, ReadiumPublication> = new Map();

  /**
   * Fetch a publication manifest from `publicationURL` and cache it by
   * `pubId`. Returns the serialized manifest JSON string (same shape as
   * `getPublication` in the original god class).
   */
  async fetchAndCache(publicationURL: string): Promise<{ publication: ReadiumPublication; manifestJson: string }> {
    log.info("fetchAndCache", publicationURL);
    const { manifest, fetcher } = await fetchManifest(publicationURL);
    const publication = new ReadiumPublication({ manifest, fetcher });
    const pubId = publication.metadata.identifier ?? "unidentified";
    PublicationManager._cache.set(pubId, publication);
    log.info("Publication fetched and cached:", pubId);
    return { publication, manifestJson: JSON.stringify(manifest.serialize()) };
  }

  /**
   * Return a cached publication by id, or fetch + cache it from
   * `publicationURL` if not already present. Matches the cache-or-fetch
   * pattern used in `openPublication` in the original god class.
   */
  async getOrFetch(pubId: string, publicationURL: string): Promise<ReadiumPublication> {
    const cached = PublicationManager._cache.get(pubId);
    if (cached) {
      log.debug("getOrFetch: cache hit for", pubId);
      return cached;
    }
    log.debug("getOrFetch: cache miss for", pubId, "— fetching");
    const { manifest, fetcher } = await fetchManifest(publicationURL);
    const publication = new ReadiumPublication({ manifest, fetcher });
    PublicationManager._cache.set(pubId, publication);
    return publication;
  }

  /** Remove a publication from the cache. */
  evict(pubId: string): void {
    PublicationManager._cache.delete(pubId);
  }

  /** Remove all publications from the cache. */
  evictAll(): void {
    PublicationManager._cache.clear();
  }
}
