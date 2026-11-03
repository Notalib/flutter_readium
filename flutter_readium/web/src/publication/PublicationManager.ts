/**
 * PublicationManager — fetches publication manifests.
 *
 * Holds no cache: the reader keeps the one open publication itself, as the native
 * plugins do, and every other load is a fresh fetch.
 */

import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { fetchManifest } from "../utils/manifest";

export class PublicationManager {
  /** Fetch a publication manifest from `publicationURL`. */
  async fetch(publicationURL: string): Promise<{ publication: ReadiumPublication; manifestJson: string }> {
    const { manifest, fetcher } = await fetchManifest(publicationURL);
    const publication = new ReadiumPublication({ manifest, fetcher });
    return { publication, manifestJson: JSON.stringify(manifest.serialize()) };
  }
}
