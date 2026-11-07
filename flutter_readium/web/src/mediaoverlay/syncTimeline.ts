/**
 * Lazy media-overlay timeline store (web reference implementation).
 *
 * Startup fetches only the narration/guided-navigation JSON covering the
 * initial position; the rest of the reading order is discovered one segment
 * (one alternate document) at a time. Which JSON belongs to reading-order
 * item i is known from the manifest alone (`resolvedSegments`, no fetch), and
 * for Sync Narration the RO item's href IS the cue text file, so a text href
 * maps to its segment in O(1).
 *
 * Guided Navigation strategy 1 (single publication-level document) has one
 * fetch total and is NOT streamed — `forPublication` returns null for it and
 * callers keep the eager parse path.
 */

import { Link, Resource } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { linkTemplateContext, resolveLink } from "../utils/linkTemplate";
import {
  SyncNarrationItem,
  enrichItemsWithToc,
  flattenToc,
  narrationAlternate,
  normalizeHref,
  parseNarrationDocument,
} from "./syncNarration";
import {
  GUIDED_NAVIGATION_MEDIA_TYPE,
  flattenGuidedNavigationDocument,
  parseGuidedNavigationDocument,
  publicationLevelGuidedNavigationLink,
} from "./guidedNavigation";

const log = createLogger("SyncTimeline");

/** Number of reading-order segments kept loaded ahead of the playhead. */
export const LOOKAHEAD_SEGMENTS = 3;

/** Consecutive fetch/parse failures after which a segment is skipped. */
const MAX_SEGMENT_FAILURES = 2;

export type SyncTimelineKind = "syncNarration" | "guidedNavigation";

export class SyncTimelineStore {
  /** roIndex -> resolved alternate link, derived from the manifest only. */
  private readonly resolvedSegments = new Map<number, Link>();
  /** resolved alternate href -> parsed items (shared GN docs fetch once). */
  private readonly parsedByHref = new Map<string, SyncNarrationItem[]>();
  /** Background lookahead task (set by prepareWindow); see settle(). */
  private lookahead: Promise<void> | undefined;
  /** resolved alternate href -> in-flight fetch (de-dupes concurrent loads). */
  private readonly inFlight = new Map<string, Promise<SyncNarrationItem[] | null>>();
  private disposed = false;
  private readonly failures = new Map<string, number>();
  /** roIndex -> items, kept in ascending RO order by {@link items}. */
  private readonly loaded = new Map<number, SyncNarrationItem[]>();

  private constructor(
    private readonly publication: ReadiumPublication,
    readonly kind: SyncTimelineKind,
    private readonly toc: Link[]
  ) {}

  /**
   * Builds a store over the publication's per-reading-order alternates, or
   * returns null when streaming does not apply (GN strategy 1, or no
   * alternates at all — the latter keeps the eager-parser contract used by
   * tests/fallback publications).
   */
  static forPublication(
    publication: ReadiumPublication,
    kind: SyncTimelineKind
  ): SyncTimelineStore | null {
    if (kind === "guidedNavigation" && publicationLevelGuidedNavigationLink(publication)) {
      // Strategy 1: one document covers the whole book — eager parse stays.
      return null;
    }
    const store = new SyncTimelineStore(publication, kind, flattenToc(publication));
    for (let i = 0; i < publication.readingOrder.items.length; i++) {
      const roLink = publication.readingOrder.items[i];
      const alternate = store._alternateFor(roLink);
      if (!alternate) continue;
      const resolved = resolveLink(
        alternate,
        linkTemplateContext(roLink, alternate),
        publication.baseURL
      );
      if (resolved.ok) store.resolvedSegments.set(i, resolved.link);
    }
    return store.resolvedSegments.size > 0 ? store : null;
  }

  /** RO indexes that declare an alternate, ascending. */
  segmentIndexes(): number[] {
    return Array.from(this.resolvedSegments.keys()).sort((a, b) => a - b);
  }

  isLoaded(roIndex: number): boolean {
    return this.loaded.has(roIndex);
  }

  /** First segment index >= `from` that is neither loaded nor exhausted. */
  nextLoadableSegment(from: number): number | undefined {
    for (const i of this.segmentIndexes()) {
      if (i < from) continue;
      const href = this.resolvedSegments.get(i)!.href;
      if (!this.loaded.has(i) && (this.failures.get(href) ?? 0) < MAX_SEGMENT_FAILURES) {
        return i;
      }
    }
    return undefined;
  }

  /** Index of the segment covering `textHref`, if any RO item matches. */
  roIndexForText(textHref: string): number | undefined {
    const norm = normalizeHref(textHref);
    const idx = this.publication.readingOrder.items.findIndex(
      (l) => normalizeHref(l.href) === norm
    );
    return idx === -1 ? undefined : idx;
  }

  /** Segment carrying cues for `audioHref`, undefined when unloaded/unknown. */
  roIndexForAudio(audioHref: string | undefined): number | undefined {
    if (!audioHref) return undefined;
    const tail = (href: string) => href.split("#")[0].split("/").pop() ?? href;
    for (const [index, items] of this.loaded) {
      if (items.some((item) => item.audioHref === audioHref || tail(item.audioHref) === tail(audioHref))) {
        return index;
      }
    }
    return undefined;
  }

  /** Fetch + parse one alternate; cached, de-duplicated, failure-counted. */
  loadSegment(roIndex: number): Promise<SyncNarrationItem[] | null> {
    const link = this.resolvedSegments.get(roIndex);
    if (!link) return Promise.resolve(null);
    const cached = this.loaded.get(roIndex);
    if (cached) return Promise.resolve(cached);
    const href = link.href;
    const inflight = this.inFlight.get(href);
    if (inflight) {
      return inflight.then((items) => {
        if (items) this.loaded.set(roIndex, items);
        return items;
      });
    }
    if ((this.failures.get(href) ?? 0) >= MAX_SEGMENT_FAILURES) {
      return Promise.resolve(null);
    }
    const task = this.fetchSegment(roIndex, link)
      .then((items) => {
        if (items) {
          this.parsedByHref.set(href, items);
          // A shared document (GN dedupe) satisfies every RO index pointing at
          // it, but its items count once: attach the array to the first index
          // only, so `items()` never duplicates it.
          let attached = false;
          for (const [i, l] of this.resolvedSegments) {
            if (l.href !== href) continue;
            this.loaded.set(i, attached ? [] : items);
            attached = true;
          }
        } else {
          this.registerFailure(href);
        }
        return items;
      })
      .catch((err) => {
        log.warn(`Failed to fetch/parse segment ${roIndex} (${href})`, err);
        this.registerFailure(href);
        return null;
      })
      .finally(() => {
        this.inFlight.delete(href);
      });
    this.inFlight.set(href, task);
    return task;
  }

  /** Load the segment covering `textHref`. True when its cues are available. */
  async ensureSegmentForText(textHref: string): Promise<boolean> {
    const roIndex = this.roIndexForText(textHref);
    if (roIndex === undefined) return false;
    if (this.loaded.has(roIndex)) return true;
    const items = await this.loadSegment(roIndex);
    return items !== null;
  }

  /** All parsed items, ordered by reading-order segment. */
  items(): SyncNarrationItem[] {
    return this.segmentIndexes().flatMap((i) => this.loaded.get(i) ?? []);
  }

  /** The merged item array with the given index loaded and the next K segments requested. */
  async prepareWindow(roIndex: number): Promise<SyncNarrationItem[]> {
    await this.loadSegment(roIndex);
    this.lookahead = this.fillAhead(roIndex).then(() => { this.lookahead = undefined; });
    return this.items();
  }

  /** Await the in-flight background lookahead (test/recovery seam). */
  async settle(): Promise<void> {
    while (this.lookahead) {
      await this.lookahead.catch(() => undefined);
    }
  }

  /**
   * Load until at most LOOKAHEAD_SEGMENTS segments sit ahead of `roIndex`
   * (already-loaded ones count toward the budget, so repeated calls from the
   * tick loop are no-ops once the window is full — without the count, each
   * call would grow the window by K again and prefetch the whole book).
   */
  async fillAhead(roIndex: number): Promise<void> {
    let ahead = 0;
    for (const i of this.resolvedSegments.keys()) {
      if (i > roIndex && this.loaded.has(i)) ahead++;
    }
    let loadedCount = ahead;
    let from = roIndex + 1;
    while (!this.disposed && loadedCount < LOOKAHEAD_SEGMENTS) {
      const next = this.nextLoadableSegment(from);
      if (next === undefined) return;
      await this.loadSegment(next);
      loadedCount++;
      from = next + 1;
    }
  }

  /** Stop background lookahead after the owning session is disposed. */
  cancelPending(): void {
    this.disposed = true;
  }

  /** Highest loaded segment index, or -1. */
  loadedTailIndex(): number {
    let tail = -1;
    for (const i of this.resolvedSegments.keys()) {
      if (this.loaded.has(i)) tail = Math.max(tail, i);
    }
    return tail;
  }

  /** Highest RO index that declares an alternate, or -1. */
  lastSegmentIndex(): number {
    let last = -1;
    for (const i of this.resolvedSegments.keys()) last = Math.max(last, i);
    return last;
  }

  /**
   * Book-wide total duration (seconds) without fetching anything: declared
   * `metadata.duration` when present, else the sum of RO items' declared
   * durations (undefined when any is missing — the window-relative totals then
   * grow with the timeline, an accepted tradeoff from the plan).
   */
  totalDurationSecs(): number | undefined {
    const metadata: unknown = this.publication.manifest.serialize().metadata;
    if (
      metadata &&
      typeof metadata === "object" &&
      "duration" in metadata &&
      typeof metadata.duration === "number" &&
      metadata.duration > 0
    ) {
      return metadata.duration;
    }
    // No declared book duration: totals come from RO items' declared durations
    // only — cue-sums of unloaded segments are unknowable without fetching, and
    // window-relative totals that grow per extension are the accepted fallback.
    const items = this.publication.readingOrder.items;
    if (items.length === 0) return undefined;
    let sum = 0;
    for (const item of items) {
      if (item.duration === undefined || item.duration <= 0) return undefined;
      sum += item.duration;
    }
    return sum > 0 ? sum : undefined;
  }

  /**
   * Sum of durations of the segments before `roIndex`, for book-wide audio
   * progression. Per segment: declared RO duration, else cue-sum of its loaded
   * items; undefined when any preceding segment is unloaded and undeclared.
   */
  cumulativeBefore(roIndex: number): number | undefined {
    let sum = 0;
    for (let i = 0; i < roIndex; i++) {
      if (!this.resolvedSegments.has(i)) continue; // no audio in this RO item; duration unknown→0? treat via declared
      const dur = this.segmentDurationSecs(
        this.publication.readingOrder.items[i]?.duration,
        this.loaded.get(i)
      );
      if (dur === undefined) return undefined;
      sum += dur;
    }
    return sum;
  }

  /** Declared duration when present, else cue-sum of the segment's items. */
  segmentDurationSecs(
    declared: number | undefined,
    items: SyncNarrationItem[] | undefined
  ): number | undefined {
    if (declared !== undefined && declared > 0) return declared;
    if (!items) return undefined;
    let cueSum = 0;
    let any = false;
    for (const item of items) {
      if (item.audioStart !== null && item.audioEnd !== null && item.audioEnd > item.audioStart) {
        cueSum += item.audioEnd - item.audioStart;
        any = true;
      }
    }
    return any ? cueSum : undefined;
  }

  // -------------------------------------------------------------------------

  private registerFailure(href: string): void {
    this.failures.set(href, (this.failures.get(href) ?? 0) + 1);
  }

  private _alternateFor(roLink: Link): Link | null {
    if (this.kind === "syncNarration") return narrationAlternate(roLink);
    return roLink.alternates?.findWithMediaType(GUIDED_NAVIGATION_MEDIA_TYPE) ?? null;
  }

  private async fetchSegment(roIndex: number, link: Link): Promise<SyncNarrationItem[] | null> {
    const resource: Resource = this.publication.get(link);
    const json = await resource.readAsJSON();
    if (this.kind === "syncNarration") {
      const roLink = this.publication.readingOrder.items[roIndex];
      const items = parseNarrationDocument(json, roIndex, roLink?.duration, this.toc);
      return items.map((item) => ({
        ...item,
        tocTitle: this.toc.find((l) => l.href === item.tocHref)?.title,
      }));
    }
    const gnDocument = parseGuidedNavigationDocument(json);
    if (!gnDocument) {
      log.warn(`Guided navigation segment ${roIndex} had no usable 'guided' entries`);
      return null;
    }
    const items: SyncNarrationItem[] = [];
    flattenGuidedNavigationDocument(gnDocument, items, this.publication);
    // Sliding-window ToC enrichment runs per segment; a chapter spanning two
    // documents can miss cross-boundary title inheritance (accepted: titles
    // fall back to cue owners, and playback never depends on tocTitle).
    return enrichItemsWithToc(items, this.publication);
  }
}
