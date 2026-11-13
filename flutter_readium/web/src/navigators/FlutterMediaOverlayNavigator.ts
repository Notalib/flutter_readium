/**
 * Media Overlay navigator for the web platform.
 *
 * Mirrors FlutterMediaOverlayNavigator in the Swift/Kotlin plugin layers.
 *
 * Strategy:
 *  1. Resolve the publication's Sync Narration / Guided Navigation alternates
 *     into a lazy timeline (see syncTimeline.ts); only the segment covering the
 *     initial position is fetched before playback starts. A background
 *     lookahead extends the window and rebuilds the audio navigator in place.
 *  2. Build a synthetic audio reading-order (one Link per unique audio file)
 *     from the loaded segments.
 *  3. Hand the synthetic publication to AudioNavigator (same path as audiobooks).
 *  4. Intercept positionChanged to map audio time -> text locator and emit dual
 *     state/locator events matching iOS/Android behaviour.
 */

import { getTime, Link, Locator, LocatorLocations, Manifest, Profile, type Fetcher } from "@readium/shared";
import { ReadiumWebError, ReadiumWebErrorCode, ResourceReadErrorReason } from "../errors/ReadiumWebError";
import { AudioNavigator } from "@readium/navigator";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import {
  AudioLocatorMapper,
  FlutterAudioNavigator,
  StreamingTimeline,
} from "../navigators/FlutterAudioNavigator";
import {
  SyncNarrationItem,
  combinedLocatorForItem,
  findItemByAudioTime,
  flattenToc,
  parseSyncNarration,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "../mediaoverlay/syncNarration";
import { parseGuidedNavigation } from "../mediaoverlay/guidedNavigation";
import { SyncTimelineKind, SyncTimelineStore } from "../mediaoverlay/syncTimeline";
import { UncuedTocTargets } from "../mediaoverlay/uncuedTocTargets";

const log = createLogger("MediaOverlay");

/** Rebuild the window when less than this many seconds remain on the last known track. */
const LOOKAHEAD_MARGIN_S = 60;

type SetNav = (nav: AudioNavigator, items: SyncNarrationItem[], uncuedTocTargets?: UncuedTocTargets) => void;
type OnTextLocatorChanged = (locator: Locator, durationMs: number | undefined) => void;

interface BuiltNavigatorParts {
  syntheticPub: ReadiumPublication;
  uncuedTocTargets: UncuedTocTargets | undefined;
}

/**
 * Initialises a Media Overlay session backed by Sync Narration JSON alternates.
 *
 * @param publication            The EPUB publication (must have Sync Narration alternates).
 * @param initialLocator         Optional starting text locator (will be mapped to audio time).
 * @param prefsJson              Dart AudioPreferences JSON string.
 * @param setNav                 Callback invoked once AudioNavigator is ready. Receives the
 *                               navigator, the parsed SyncNarrationItem list and the uncued
 *                               ToC target resolver so callers can run text→audio mapping on
 *                               subsequent navigation events. The item array is live: a
 *                               streaming session grows it in place as segments load.
 * @param onTextLocatorChanged   Optional callback fired each time the active Sync Narration
 *                               cue advances to a new text locator. Used by ReadiumReader to
 *                               apply utterance-level decorations on the visual navigator.
 *                               Receives the text locator and the cue duration in milliseconds.
 * @param bridge                 Bridge for audio streaming error events (e.g. AudioStreamAuthError).
 * @returns the session handle (window extension / lazy seeks), or undefined when
 *           no playable items were found.
 */
export async function initializeMediaOverlayNavigator(
  publication: ReadiumPublication,
  initialLocator: Locator | undefined,
  prefsJson: string,
  setNav: SetNav,
  onTextLocatorChanged?: OnTextLocatorChanged,
  bridge?: ReadiumBridge
): Promise<MediaOverlaySession | undefined> {
  return MediaOverlaySession.start(
    publication, initialLocator, prefsJson, setNav, onTextLocatorChanged, "SyncNarration", bridge
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
  setNav: SetNav,
  onTextLocatorChanged?: OnTextLocatorChanged,
  bridge?: ReadiumBridge
): Promise<MediaOverlaySession | undefined> {
  return MediaOverlaySession.start(
    publication, initialLocator, prefsJson, setNav, onTextLocatorChanged, "GuidedNavigation", bridge
  );
}

/**
 * One Media Overlay playback session. Owns the (possibly streaming) timeline
 * store, the live resolved cue list, and the audio navigator — window
 * extensions rebuild the navigator in place at the current audio locator.
 */
export class MediaOverlaySession implements StreamingTimeline {
  /**
   * Live cue list handed to setNav; grown in place as segments load so every
   * consumer of the array identity (the mapper, ReadiumReader._syncItems)
   * immediately sees newly loaded cues.
   */
  private readonly items: SyncNarrationItem[] = [];
  private nav: AudioNavigator | undefined;
  private ownerTargets: UncuedTocTargets | undefined;
  private rebuild: Promise<void> | undefined;
  private lookaheadQueued = false;
  private disposed = false;
  /** Last playback state seen by the mapper, used to resume across rebuilds. */
  private playbackWasActive = false;
  private lastDetailedTextLocatorKey: string | undefined;
  private lastPublicTextLocatorKey: string | undefined;

  private constructor(
    private readonly publication: ReadiumPublication,
    private prefsJson: string,
    private readonly setNav: SetNav,
    private readonly onTextLocatorChanged: OnTextLocatorChanged | undefined,
    private readonly sourceLabel: string,
    private readonly bridge: ReadiumBridge | undefined,
    /** Null on the eager fallback path (no alternates / initial window empty). */
    private store: SyncTimelineStore | null
  ) {}

  /**
   * Loads the initial window (or parses everything for the eager fallback) and
   * starts playback. A store is only used when it covers at least one alternate
   * and the initial segment yields cues; otherwise the eager full-parse path —
   * the Step-1 parallelized parser — takes over.
   */
  static async start(
    publication: ReadiumPublication,
    initialLocator: Locator | undefined,
    prefsJson: string,
    setNav: SetNav,
    onTextLocatorChanged: OnTextLocatorChanged | undefined,
    sourceLabel: string,
    bridge: ReadiumBridge | undefined
  ): Promise<MediaOverlaySession | undefined> {
    const kind: SyncTimelineKind = sourceLabel === "SyncNarration" ? "syncNarration" : "guidedNavigation";
    let store: SyncTimelineStore | null = null;
    try {
      store = SyncTimelineStore.forPublication(publication, kind);
    } catch (err) {
      // Tests and hand-rolled publications may not expose the manifest shape
      // the store needs; the eager parsers are more forgiving.
      log.warn(`Timeline store unavailable (${sourceLabel}); using eager parse`, err);
    }

    const session = new MediaOverlaySession(
      publication, prefsJson, setNav, onTextLocatorChanged, sourceLabel, bridge, store
    );

    let items: SyncNarrationItem[] | undefined;
    if (store) {
      const requested = initialLocator ? store.roIndexForText(initialLocator.href) : undefined;
      const start = session._nearestSegment(store, requested ?? 0);
      items = await store.prepareWindow(start);
      if (items.length === 0) {
        log.warn(`Streaming timeline produced no items for ${sourceLabel}; falling back to eager parse`);
        session.store = null;
      }
    }
    if (!session.store) {
      items = sourceLabel === "SyncNarration"
        ? await parseSyncNarration(publication)
        : await parseGuidedNavigation(publication);
    }

    if (!items || items.length === 0) {
      log.warn(`No items found from ${sourceLabel}; aborting.`);
      return undefined;
    }
    log.info(
      `Initializing MediaOverlayNavigator (source: ${sourceLabel})`,
      initialLocator ? `from text locator ${initialLocator.href}` : "(no initial locator)"
    );
    log.info(
      `Loaded ${items.length} items across ${new Set(items.map((i) => i.audioHref)).size} audio file(s)` +
      (session.store ? " (streaming window)" : " (eager)")
    );

    await session._buildInitial(items, initialLocator);
    return session;
  }

  dispose(): void {
    this.disposed = true;
    this.store?.cancelPending();
  }

  /** Keeps window rebuilds on the latest preferences after a runtime change. */
  setPreferences(preferencesJson: string): void {
    this.prefsJson = preferencesJson;
  }

  /** Await any in-flight window extension (test seam). Startup no longer prefetched. */
  settle(): Promise<void> {
    return this.awaitIdle();
  }

  // -------------------------------------------------------------------------
  // StreamingTimeline (consulted by FlutterAudioNavigator)
  // -------------------------------------------------------------------------

  totalDurationMs(): number | undefined {
    const book = this.store?.totalDurationSecs();
    return book === undefined ? undefined : Math.round(book * 1000);
  }

  locatorProgression(audioLocator: Locator): number | undefined {
    const store = this.store;
    if (!store) return undefined;
    const total = store.totalDurationSecs();
    if (total === undefined || total <= 0) return undefined;
    const roIndex = store.roIndexForAudio(audioLocator.href);
    if (roIndex === undefined) return undefined;
    const before = store.cumulativeBefore(roIndex);
    if (before === undefined) return undefined;
    const time = getTime(audioLocator.locations) ?? 0;
    return Math.min(1, Math.max(0, (before + time) / total));
  }

  /**
   * Last known track ended. Extend the window and rebuild when more segments
   * exist; true means "playback continues" (the ended emission is suppressed).
   * False → honest end (no loadable segment remains or every load failed).
   */
  async takeOverAtEdge(): Promise<boolean> {
    if (this.disposed || !this.store) return false;
    const before = this.items.length;
    if (this.rebuild) {
      await this.rebuild.catch(() => undefined);
      if (this.disposed) return false;
      // The joined rebuild took the edge over only if it grew the live window
      // AND left a working navigator; a failed rebuild must not swallow ended.
      if (this.items.length > before && this.nav) return true;
    }
    const store = this.store;
    // Load segments past the playhead one at a time, advancing past slots at the
    // failure cap, until one grows the live window. The K-ahead lookahead budget
    // can stop on exhausted slots; a healthy segment beyond them must still
    // extend the window before an honest end is conceded (ADR 0003 "honest end").
    let playhead =
      store.roIndexForAudio(this.nav?.currentLocator.href) ?? store.loadedTailIndex();
    let next = store.nextLoadableSegment(playhead + 1);
    while (next !== undefined) {
      await store.loadSegment(next);
      await this.extend();
      if (this.items.length > before) break;
      if (this.disposed || !this.nav) return false;
      // Advance only past a settled slot; a within-cap failure stays put and is
      // retried next pass (mirrors fillAhead), so one flaky read can't skip it.
      if (store.isSettled(next)) playhead = next;
      next = store.nextLoadableSegment(playhead + 1);
    }
    return this.items.length > before && !this.disposed && !!this.nav;
  }

  // -------------------------------------------------------------------------
  // Window management
  // -------------------------------------------------------------------------

  /** Await all in-flight window extensions (public seam for callers seeking). */
  async awaitIdle(): Promise<void> {
    while (this.rebuild) {
      await this.rebuild.catch(() => undefined);
    }
  }

  /**
   * Ensure cues + the audio playlist cover `textHref` (seek/goTo beyond the
   * loaded window). Returns once the LIVE navigator can play the target track:
   * awaiting the in-flight lookahead alone is not enough — that rebuild resumes
   * at the OLD position, so loop until the target is fetched and any queue
   * extension it triggered has settled.
   */
  async ensureWindowForText(textHref: string): Promise<void> {
    const store = this.store;
    if (!store || this.disposed) return;
    // Bounded: each pass settles in-flight extensions, fetches the target
    // segment, and extends once when the merged window outgrew the live one.
    // A pass that lands nothing new returns, so this converges.
    for (let attempt = 0; attempt < 3; attempt++) {
      await this.awaitIdle();
      if (this.disposed) return;
      const roIndex = store.roIndexForText(textHref);
      if (roIndex === undefined) return;
      await store.ensureSegmentForText(textHref);
      const playhead =
        store.roIndexForAudio(this.nav?.currentLocator.href) ?? store.loadedTailIndex();
      await store.fillAhead(playhead);
      if (store.items().length <= this.items.length) return;
      await this.extend(); // awaits the rebuild; next pass re-checks convergence
    }
    await this.awaitIdle();
  }

  /** Rebuild the navigator with the store's merged items, if it changed. */
  private async extend(): Promise<void> {
    if (this.rebuild) {
      await this.rebuild.catch(() => undefined);
      return;
    }
    const store = this.store;
    if (!store) return;
    const merged = store.items();
    if (merged.length <= this.items.length) return;
    const audioLocator = this.nav?.currentLocator;
    const wasPlaying = this.playbackWasActive;
    this.rebuild = (async () => {
      try {
        const built = await this._resolveAndEnrich(merged);
        await this._createNavigator(built, audioLocator, wasPlaying);
      } finally {
        this.rebuild = undefined;
      }
    })();
    await this.rebuild.catch((err) => {
      log.warn("Window extension rebuild failed", err);
    });
  }

  /** Queue a lookahead refresh if the playhead is close to the window edge. */
  private maybeExtendFrom(nav: AudioNavigator): void {
    const store = this.store;
    if (!store || this.disposed || this.rebuild || this.lookaheadQueued || !nav.isPlaying) return;
    // Guard and budget both from the PLAYHEAD's segment: after a backward seek the
    // loaded tail sits ahead, and a tail-based check would disable lookahead here
    // while fillAhead (below) still fills from the playhead.
    const roIndex =
      store.roIndexForAudio(nav.currentLocator.href) ?? store.loadedTailIndex();
    if (store.nextLoadableSegment(roIndex + 1) === undefined) return;
    const duration = nav.duration;
    if (!duration || duration <= 0) return;
    if (duration - nav.currentTime > LOOKAHEAD_MARGIN_S) return;
    this.lookaheadQueued = true;
    void (async () => {
      try {
        await store.fillAhead(roIndex);
        await this.extend();
      } catch (err) {
        log.warn("Lookahead segment load failed", err);
      } finally {
        this.lookaheadQueued = false;
      }
    })();
  }

  // -------------------------------------------------------------------------
  // Navigator construction
  // -------------------------------------------------------------------------

  /** Initial construction path: resolve/enrich, anchor initial locator, create nav. */
  private async _buildInitial(
    items: SyncNarrationItem[],
    initialLocator: Locator | undefined
  ): Promise<void> {
    const built = await this._resolveAndEnrich(items);
    const anchored = initialLocator && built.uncuedTocTargets
      ? await built.uncuedTocTargets.anchor(initialLocator)
      : initialLocator;
    const audioInitialLocator = anchored
      ? textLocatorToAudioLocator(this.items, anchored, true, this.sourceLabel === "SyncNarration")
      : undefined;
    if (initialLocator) {
      log.info(
        audioInitialLocator
          ? `Initial text locator mapped to audio ${audioInitialLocator.href} ${audioInitialLocator.locations?.fragments?.[0] ?? ""}`
          : "Initial text locator could not be mapped to an audio item — starting at beginning"
      );
    }
    await this._createNavigator(built, audioInitialLocator, false);
    this._emitInitialCue(audioInitialLocator);
  }

  /**
   * Resolve relative audio hrefs + uncued-owner enrichment for a merged item
   * list, publishing the result into the live `items` array (mutated in place
   * so setNav consumers keep the same array identity across rebuilds).
   */
  private async _resolveAndEnrich(items: SyncNarrationItem[]): Promise<BuiltNavigatorParts> {
    const audioReadingOrder = _buildAudioReadingOrder(items, this.publication);
    const resolvedItems = _resolveItemHrefs(items, audioReadingOrder);
    // UncuedTocTargets corrects tocHref/tocTitle in place, but the store hands
    // back the uncorrected parse each rebuild and its per-resource fill cache
    // never re-runs, so carry the corrections onto the fresh copies.
    // Cue identity: textId repeats across documents (p1 in each), so scope by href.
    const cueKey = (item: SyncNarrationItem) =>
      `${item.textHref}#${item.textId}#${item.audioStart ?? ""}`;
    const corrected = new Map<string, SyncNarrationItem>();
    for (const item of this.items) {
      if (item.tocHref) corrected.set(cueKey(item), item);
    }
    // Publish into the live array first: UncuedTocTargets is constructed with
    // `this.items`, so its cue lookups see window extensions without rebuild.

    this.items.length = 0;
    this.items.push(...resolvedItems);
    if (corrected.size > 0) {
      for (const item of this.items) {
        const saved = corrected.get(cueKey(item));
        if (saved) {
          item.tocHref = saved.tocHref;
          item.tocTitle = saved.tocTitle;
        }
      }
    }
    // One UncuedTocTargets per session (both sources — Guided Navigation gets
    // the same XHTML owner correction, only the anchor seek policy differs):
    // its XHTML/owner caches are resource-keyed, so re-running prepareOwners()
    // only pays for newly loaded resources after a window extension.
    if (!this.ownerTargets) {
      this.ownerTargets = new UncuedTocTargets(this.publication, this.items, flattenToc(this.publication));
    }
    await this.ownerTargets.prepareOwners();
    // Owner correction can change an audio file's first ToC title, so titles come from the corrected items.
    const syntheticPub = _buildAudiobookPublication(
      this.publication,
      _withCueTitles(audioReadingOrder, this.items)
    );
    return {
      syntheticPub,
      uncuedTocTargets: this.sourceLabel === "SyncNarration" ? this.ownerTargets : undefined,
    };
  }

  private async _createNavigator(
    built: BuiltNavigatorParts,
    audioLocator: Locator | undefined,
    resumePlaying: boolean
  ): Promise<void> {
    const mapper: AudioLocatorMapper = (nav, navLocator) => {
      this.playbackWasActive = nav.isPlaying;
      if (this.rebuild && nav !== this.nav) {
        // Mid window-extension: the outgoing navigator's trailing events must
        // not emit cues mapped from the new merged list. Suppress the state
        // event; the rebuilt navigator re-reports the position.
        return {};
      }
      this.maybeExtendFrom(nav);
      const resolvedTime = getTime(navLocator.locations) ?? nav.currentTime;
      const item = findItemByAudioTime(
        this.items, navLocator.href, resolvedTime, this.sourceLabel === "SyncNarration"
      );
      if (item) {
        if (!item.tocHref) void this.ownerTargets?.fillOwners(item.textHref);
        const detailedTextLocator = textLocatorForItem(item);
        const publicTextLocator = _coarseLocatorForPublicEvent(detailedTextLocator);

        const detailedKey = JSON.stringify(detailedTextLocator.serialize());
        const shouldEmitDetailedTextLocator = detailedKey !== this.lastDetailedTextLocatorKey;
        if (shouldEmitDetailedTextLocator) this.lastDetailedTextLocatorKey = detailedKey;

        const publicKey = JSON.stringify(publicTextLocator.serialize());
        const shouldEmitPublicTextLocator = publicKey !== this.lastPublicTextLocatorKey;
        if (shouldEmitPublicTextLocator) this.lastPublicTextLocatorKey = publicKey;

        return {
          stateLocator: combinedLocatorForItem(item, navLocator),
          textLocator: shouldEmitDetailedTextLocator ? detailedTextLocator : undefined,
          publicTextLocator: shouldEmitPublicTextLocator ? publicTextLocator : undefined,
        };
      }
      return {};
    };

    // Wrap the caller's callback to enrich it with the cue duration.
    // The AudioLocatorMapper knows which SyncNarrationItem is active, but the
    // callback signature at the audioNavigator layer doesn't carry that info.
    // Instead, we re-derive the item here from the text locator fragment by
    // matching against the live item list — same lookup the mapper does, just
    // keyed on the text side.
    const wrappedCallback: OnTextLocatorChanged | undefined = this.onTextLocatorChanged
      ? (locator, _ignored) => {
          const fragId = locator.locations?.fragments?.[0];
          const item = fragId
            ? this.items.find((i) => i.textId === fragId)
            : undefined;
          const durationMs =
            item?.audioStart != null && item?.audioEnd != null
              ? (item.audioEnd - item.audioStart) * 1000
              : undefined;
          log.debug(
            `[mediaOverlay] cue fragment="${fragId ?? "(none)"}" ` +
            `item=${item ? `audioStart=${item.audioStart} audioEnd=${item.audioEnd}` : "NOT FOUND"} ` +
            `→ durationMs=${durationMs ?? "undefined"}`
          );
          this.onTextLocatorChanged!(locator, durationMs);
        }
      : undefined;

    // Tear the old navigator down before creating the replacement so two
    // media elements never play concurrently (mirrors rebuildAndVerifyPlayback).
    const previous = this.nav;
    const wasPlaying = resumePlaying || (!!previous && this.playbackWasActive);
    if (previous) {
      previous.stop();
      previous.destroy();
      this.nav = undefined;
    }

    await FlutterAudioNavigator.create(
      built.syntheticPub,
      audioLocator,
      this.prefsJson,
      (nav: AudioNavigator) => {
        if (this.disposed) {
          nav.stop();
          nav.destroy();
          return;
        }
        this.nav = nav;
        this.setNav(nav, this.items, built.uncuedTocTargets);
      },
      mapper,
      wrappedCallback,
      // Media overlay cue synchronisation requires finer granularity than the
      // Dart-side updateIntervalSecs preference (which controls the progress bar).
      // 100ms keeps panel panning within one frame of the audio cue boundary.
      100,
      this.bridge,
      // Streaming window rebuilds are not initial opens: a hiccup here must
      // not surface as a create-timeout error to Dart.
      false,
      undefined,
      this.store ? this : undefined
    );

    const nav = this.nav;
    if (nav && wasPlaying) {
      FlutterAudioNavigator.setPlaybackIntent(true);
      nav.play();
    }
  }

  /** Fire the initial cue callback exactly as the eager path used to. */
  private _emitInitialCue(audioInitialLocator: Locator | undefined): void {
    if (!this.onTextLocatorChanged) return;
    const fragment = audioInitialLocator?.locations?.fragments?.[0];
    const initTime = fragment?.startsWith("t=") ? parseFloat(fragment.slice(2)) : 0;
    const initHref = audioInitialLocator?.href ?? this.items[0]?.audioHref;
    const initItem = initHref
      ? findItemByAudioTime(this.items, initHref, initTime, this.sourceLabel === "SyncNarration") ?? this.items[0]
      : this.items[0];
    if (!initItem) return;
    const initDurationMs =
      initItem.audioStart != null && initItem.audioEnd != null
        ? (initItem.audioEnd - initItem.audioStart) * 1000
        : undefined;
    this.onTextLocatorChanged(textLocatorForItem(initItem), initDurationMs);
  }

  // -------------------------------------------------------------------------
  // Lookups
  // -------------------------------------------------------------------------

  private _nearestSegment(store: SyncTimelineStore, roIndex: number): number {
    const indexes = store.segmentIndexes();
    if (indexes.length === 0) return roIndex;
    if (indexes.includes(roIndex)) return roIndex;
    const atOrBefore = indexes.filter((i) => i <= roIndex);
    return atOrBefore.length > 0 ? atOrBefore[atOrBefore.length - 1] : indexes[0];
  }

}

/**
 * Strips cue-level detail (fragment/comicRegion/cssSelector/highlight) from a
 * locator so Dart-side `onTextLocatorChanged` can track stable reading
 * position (href + 1-based page position) without panel-level churn.
 */
function _coarseLocatorForPublicEvent(locator: Locator): Locator {
  const tocHref = locator.locations?.otherLocations?.get("tocHref");
  const otherLocations = tocHref != null ? new Map<string, unknown>([["tocHref", tocHref]]) : undefined;
  return new Locator({
    href: locator.href,
    type: locator.type,
    title: locator.title,
    locations: new LocatorLocations({
      position: locator.locations?.position,
      otherLocations,
    }),
  });
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/**
 * Resolves relative `audioHref` values in items to the absolute hrefs used in
 * the synthetic reading order. The narration JSON stores relative paths; the
 * reading order and AudioNavigator locators use absolute URLs. Any item whose
 * relative href matches a reading-order entry via suffix comparison is updated
 * in place; unmatched items are left unchanged.
 */
function _resolveItemHrefs(
  items: SyncNarrationItem[],
  audioReadingOrder: Link[]
): SyncNarrationItem[] {
  return items.map((item) => {
    const absLink = audioReadingOrder.find(
      (l) => l.href === item.audioHref || l.href.endsWith("/" + item.audioHref)
    );
    return absLink ? { ...item, audioHref: absLink.href } : item;
  });
}

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
    { cueSum: number; declaredDuration?: number }
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
  }

  // Absolutize the self link against the document origin before deriving the
  // base URL. If the manifest's self link is relative/root-relative (e.g. a
  // publication served at "/test-fixtures/overlay/manifest.json"), a non-absolute
  // base produces non-absolute audio hrefs, which the upstream AudioNavigator then
  // resolves a *second* time against the publication base — doubling the
  // sub-path (".../overlay/overlay/01.mp3" → 404). Fully-qualifying
  // here makes the synthetic hrefs absolute so upstream leaves them untouched.
  // Already-absolute self links (e.g. remote "https://…/manifest.json") are
  // returned unchanged by `new URL`.
  const rawSelfHref = publication.manifest.linksWithRel("self")[0]?.href ?? "";
  const selfHref =
    rawSelfHref && typeof window !== "undefined"
      ? new URL(rawSelfHref, window.location.href).href
      : rawSelfHref;
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
      duration,
    });
  });
}

/** Titles each audio link with the first ToC title among its cues. */
function _withCueTitles(audioReadingOrder: Link[], items: SyncNarrationItem[]): Link[] {
  const titles = new Map<string, string>();
  for (const item of items) {
    if (item.tocTitle && !titles.has(item.audioHref)) titles.set(item.audioHref, item.tocTitle);
  }
  return audioReadingOrder.map((link) => new Link({
    href: link.href,
    type: link.type,
    title: titles.get(link.href),
    duration: link.duration,
  }));
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

  const manifest = Manifest.deserialize(manifestJson);
  if (!manifest) {
    throw new ReadiumWebError(
      "Failed to create new Audiobook manifest",
      ReadiumWebErrorCode.resourceReadError,
      { reason: ResourceReadErrorReason.manifestDeserialization }
    );
  }

  const selfLink = publication.manifest.linksWithRel("self")[0];
  if (selfLink?.href) manifest.setSelfLink(selfLink.href);

  // The fetcher is a private field upstream never exposed a getter for.
  const fetcher = (publication as unknown as { fetcher: Fetcher }).fetcher;
  return new ReadiumPublication({ manifest, fetcher });
}

// ---------------------------------------------------------------------------
// Test-only exports
//
// The double-underscore prefix marks these as internal — not part of the
// module's public API, only exposed for unit tests in __tests__/.
// ---------------------------------------------------------------------------

export const __testing__ = {
  audioMimeType: _audioMimeType,
  resolveItemHrefs: _resolveItemHrefs,
  buildAudioReadingOrder: _buildAudioReadingOrder,
  withCueTitles: _withCueTitles,
};
