@file:OptIn(ExperimentalReadiumApi::class)

package dk.nota.flutterreadium

import dk.nota.flutterreadium.models.FlutterMediaOverlay
import dk.nota.flutterreadium.models.GuidedNavigationDocument
import dk.nota.flutterreadium.models.guidedNavigationMediaType
import dk.nota.flutterreadium.models.toMediaOverlays
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url

private const val TAG = "SyncTimelineStore"

internal enum class SyncTimelineKind {
    SyncNarration,
    GuidedNavigation,
}

/**
 * Lazy media-overlay timeline store (Android), mirroring
 * `web/src/mediaoverlay/syncTimeline.ts`.
 *
 * Startup fetches only the narration/guided-navigation JSON covering the initial
 * position; the rest of the reading order is discovered one segment (one
 * alternate document) at a time. Which JSON belongs to reading-order item `i` is
 * known from the manifest alone ([resolvedSegments], no fetch), and for sync
 * narration the RO item's href IS the cue text file, so a text href maps to its
 * segment in O(1).
 *
 * Guided Navigation strategy 1 (one publication-level document) is a single
 * fetch and is NOT streamed: [forPublication] returns null for it so callers
 * keep the eager parse path.
 *
 * Thread safety: [loadSegment] performs its fetch on [Dispatchers.IO] and writes
 * the bookkeeping maps back in the caller's context. Callers run on the
 * navigator/reader `Dispatchers.Main.immediate` scopes, so no locking is needed.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal class SyncTimelineStore private constructor(
    /** The text publication; the pseudo audiobook is built from its alternates. */
    val sourcePublication: Publication,
    val kind: SyncTimelineKind,
) {
    /** roIndex -> resolved alternate link, derived from the manifest only. */
    private val resolvedSegments = LinkedHashMap<Int, Link>()

    /** roIndex -> parsed overlays, kept in insertion (ascending RO) order. */
    private val loaded = LinkedHashMap<Int, List<FlutterMediaOverlay>>()

    /** resolved alternate href -> consecutive fetch/parse failures. */
    private val failures = mutableMapOf<String, Int>()

    /** Set by [cancelPending]; stops an in-flight [fillAhead] loop. */
    private var disposed = false

    companion object {
        /** Number of reading-order segments kept loaded ahead of the playhead. */
        const val LOOKAHEAD_SEGMENTS = 3

        /** Rebuild the window when less than this many seconds remain on the current track. */
        const val LOOKAHEAD_MARGIN_SECONDS = 60.0

        /** Consecutive fetch/parse failures after which a segment is skipped. */
        private const val MAX_SEGMENT_FAILURES = 2

        /**
         * Builds a store over the publication's per-reading-order alternates, or
         * returns null when streaming does not apply: GN strategy 1, or no
         * alternates at all (the latter keeps the eager parser's contract).
         */
        fun forPublication(
            publication: Publication,
            kind: SyncTimelineKind,
        ): SyncTimelineStore? {
            if (!publication.hasSyncNarration()) return null
            if (kind == SyncTimelineKind.GuidedNavigation &&
                publication.links.any { it.mediaType == guidedNavigationMediaType }
            ) {
                // Strategy 1: one document covers the whole book — eager parse stays.
                return null
            }

            val store = SyncTimelineStore(publication, kind)
            val alternateMediaType =
                when (kind) {
                    SyncTimelineKind.SyncNarration -> syncNarrationsMediaType
                    SyncTimelineKind.GuidedNavigation -> guidedNavigationMediaType
                }
            publication.readingOrder.forEachIndexed { roIndex, roLink ->
                val alternate =
                    roLink.alternates.firstOrNull { it.mediaType == alternateMediaType }
                        ?: return@forEachIndexed
                val resolved =
                    resolvedTemplateLink(
                        alternate,
                        LinkTemplateResolver.parameters(roLink, alternate),
                    ) ?: return@forEachIndexed
                store.resolvedSegments[roIndex] =
                    when (kind) {
                        // Matches the eager path: sync narration overlays are titled after their RO item.
                        SyncTimelineKind.SyncNarration -> resolved.copy(title = roLink.title)
                        SyncTimelineKind.GuidedNavigation -> resolved
                    }
            }
            if (store.resolvedSegments.isEmpty()) return null
            return store
        }
    }

    /** RO indexes that declare an alternate, ascending. */
    fun segmentIndexes(): List<Int> = resolvedSegments.keys.toList()

    fun isLoaded(roIndex: Int): Boolean = loaded.containsKey(roIndex)

    /** Resolves [roIndex] to the nearest segment that actually declares an alternate. */
    fun nearestSegmentIndex(roIndex: Int): Int {
        val indexes = segmentIndexes()
        if (indexes.isEmpty()) return roIndex
        if (resolvedSegments.containsKey(roIndex)) return roIndex
        return indexes.filter { it <= roIndex }.lastOrNull() ?: indexes.first()
    }

    /** First segment index >= [from] that is neither loaded nor exhausted. */
    fun nextLoadableSegment(from: Int): Int? =
        resolvedSegments.entries
            .firstOrNull { (roIndex, link) ->
                roIndex >= from &&
                    !loaded.containsKey(roIndex) &&
                    (failures[link.href.toString()] ?: 0) < MAX_SEGMENT_FAILURES
            }?.key

    /** True when a segment beyond [tail] could still be fetched. */
    fun hasLoadableBeyond(tail: Int): Boolean = nextLoadableSegment(tail + 1) != null

    /** Index of the segment covering [textHref], if any RO item matches. */
    fun roIndexForText(textHref: String?): Int? {
        val url = textHref?.let { Url.invoke(it) } ?: return null
        return resolvedSegments.keys.firstOrNull { roIndex ->
            sourcePublication.readingOrder.getOrNull(roIndex)?.href?.resolve()?.isEquivalent(url) == true
        }
    }
    /**
     * Segment index whose loaded cues reference [audioHref], or null. Cue items store the
     * relative href from the JSON while live player locators carry the resolved (absolute) URL,
     * so an exact match falls back to a path-tail comparison.
     */
    fun roIndexForAudio(audioHref: String?): Int? {
        val href = audioHref ?: return null
        val url = Url.invoke(href)
        val path = href.substringBefore('#').trimStart('/')
        return loaded.entries.firstOrNull { (_, overlays) ->
            overlays.any { overlay ->
                overlay.items.any { item ->
                    Url.invoke(item.audioFile)?.let { url?.isEquivalent(it) } == true ||
                        item.audioFile.substringBefore('#').trimStart('/').let { it == path || path.endsWith("/$it") }
                }
            }
        }?.key
    }
    /**
     * Fetch + parse the ONE alternate document for [roIndex]. Cached, and a shared
     * guided-navigation document satisfies every RO index pointing at it (its
     * overlays count once, so [windowOverlays] never duplicates them).
     * Returns the parsed overlays, or null on failure / when the segment is exhausted.
     */
    suspend fun loadSegment(roIndex: Int): List<FlutterMediaOverlay>? {
        val link = resolvedSegments[roIndex] ?: return null
        loaded[roIndex]?.let { return it }
        val key = link.href.toString()
        if ((failures[key] ?: 0) >= MAX_SEGMENT_FAILURES) return null

        val parsed =
            try {
                fetchSegment(roIndex, link)
            } catch (e: Exception) {
                PluginLog.w(TAG, "::loadSegment - failed to fetch/parse segment $roIndex ($key): ${e.message}")
                null
            }

        if (parsed == null) {
            failures[key] = (failures[key] ?: 0) + 1
            return null
        }

        var attached = false
        for ((index, candidate) in resolvedSegments) {
            if (candidate.href.toString() != key) continue
            loaded[index] = if (attached) emptyList() else parsed
            attached = true
        }
        return parsed
    }

    /** Load the segment covering [textHref]. True when its cues are available. */
    suspend fun ensureSegmentForText(textHref: String?): Boolean {
        val roIndex = roIndexForText(textHref) ?: return false
        if (loaded.containsKey(roIndex)) return true
        return loadSegment(roIndex) != null
    }

    /**
     * Loaded overlays ascending by segment - the list handed to the navigator.
     * Cumulative: segments are never evicted behind the playhead, so earlier
     * chapters stay mappable and book-wide totals remain computable (ADR 0003
     * "cumulative forward window"). Empty when nothing is loaded (caller falls
     * back to eager parse).
     */
    fun windowOverlays(): List<FlutterMediaOverlay?> =
        loaded
            .toSortedMap()
            .values
            .flatten()
            .map { it as FlutterMediaOverlay? }

    /** Cue count of the current window; compare before/after a load to detect new cues. */
    fun loadedCueCount(): Int = loaded.values.sumOf { overlays -> overlays.sumOf { it.items.size } }

    /**
     * Ensure the next [LOOKAHEAD_SEGMENTS] segment *slots* past [roIndex] are loaded.
     * The budget is position-bound (which slots), not load-count-bound: counting loaded
     * segments anywhere ahead would let the old forward window eat the budget after a
     * backward jump - playback would then skip into that window - and one flaky pass
     * would burn the whole budget and concede an end of book while segments are still
     * loadable (ADR 0003 "honest end"). A failed load stays in its slot and is retried
     * until it loads or hits MAX_SEGMENT_FAILURES, whichever comes first.
     */
    suspend fun fillAhead(roIndex: Int) {
        val ahead = segmentIndexes().filter { it > roIndex }.take(LOOKAHEAD_SEGMENTS)
        for (i in ahead) {
            if (disposed) return
            while (!loaded.containsKey(i) &&
                (failures[resolvedSegments.getValue(i).href.toString()] ?: 0) < MAX_SEGMENT_FAILURES
            ) {
                loadSegment(i)
            }
        }
    }

    /** Highest loaded segment index, or -1. */
    fun loadedTailIndex(): Int = loaded.keys.maxOrNull() ?: -1

    /** Highest RO index that declares an alternate, or -1. */
    fun lastSegmentIndex(): Int = resolvedSegments.keys.maxOrNull() ?: -1

    /** Stop background lookahead after the owning navigator was disposed. */
    fun cancelPending() {
        disposed = true
    }

    /**
     * Book-wide total duration (seconds) without fetching anything: declared
     * `metadata.duration` when present, else the sum of RO items' declared durations
     * (null when any is missing - the window-relative totals then grow with the
     * timeline, an accepted tradeoff from the plan).
     */
    fun totalDurationSecs(): Double? {
        sourcePublication.metadata.duration?.takeIf { it.isFinite() && it > 0.0 }?.let { return it }
        val items = sourcePublication.readingOrder
        if (items.isEmpty()) return null
        var sum = 0.0
        for (item in items) {
            val duration = item.duration?.takeIf { it.isFinite() && it > 0.0 } ?: return null
            sum += duration
        }
        return sum.takeIf { it > 0.0 }
    }

    /**
     * Sum of durations of the segments before [roIndex]; null when a preceding segment has
     * neither a declared duration nor loaded cues (book-wide progression is unknown until
     * the window catches up). Mirrors web/iOS `cumulativeBefore`.
     */
    private fun cumulativeBefore(roIndex: Int): Double? {
        var sum = 0.0
        for (index in 0 until roIndex) {
            if (!resolvedSegments.containsKey(index)) continue
            val declared =
                sourcePublication.readingOrder.getOrNull(index)?.duration?.takeIf { it.isFinite() && it > 0.0 }
            val cueSum =
                loaded[index]?.sumOf { overlay ->
                    overlay.items.sumOf { item ->
                        val start = item.audioStart
                        val end = item.audioEnd
                        if (start != null && end != null && end > start) end - start else 0.0
                    }
                }
            sum += declared ?: cueSum?.takeIf { it > 0.0 } ?: return null
        }
        return sum
    }

    /**
     * Book-wide progression for an audio position, or null when the total or the segments
     * before the playhead are still unknown. The ExoPlayer locator's own totalProgression is
     * window-relative under streaming, so this is the only book-correct value.
     */
    fun locatorProgression(audioHref: String?, timeSeconds: Double?): Double? {
        val roIndex = roIndexForAudio(audioHref) ?: return null
        val total = totalDurationSecs()?.takeIf { it > 0.0 } ?: return null
        val before = cumulativeBefore(roIndex) ?: return null
        return ((before + (timeSeconds ?: 0.0)) / total).coerceIn(0.0, 1.0)
    }

    // -------------------------------------------------------------------------

    private suspend fun fetchSegment(
        roIndex: Int,
        link: Link,
    ): List<FlutterMediaOverlay>? =
        withContext(Dispatchers.IO) {
            val jsonString =
                sourcePublication.get(link)?.read()?.getOrNull()?.let { String(it) }
                    ?: run {
                        PluginLog.w(TAG, "::fetchSegment - unable to load ${link.href}")
                        return@withContext null
                    }
            when (kind) {
                SyncTimelineKind.SyncNarration -> fetchSyncNarrationSegment(roIndex, link, jsonString)
                SyncTimelineKind.GuidedNavigation -> fetchGuidedNavigationSegment(jsonString)
            }
        }

    private fun fetchSyncNarrationSegment(
        roIndex: Int,
        link: Link,
        jsonString: String,
    ): List<FlutterMediaOverlay>? {
        // The eager path requires a declared positive duration (progression math depends on it).
        val duration = link.duration?.takeIf { it > 0.0 } ?: return null
        val overlay =
            FlutterMediaOverlay.fromJson(
                JSONObject(jsonString),
                roIndex + 1,
                null,
                link.title ?: "",
                duration,
                sourcePublication.tableOfContents.flattenChildren().map { it.href.resolve() },
            ) ?: return null
        return listOf(overlay)
    }

    private fun fetchGuidedNavigationSegment(jsonString: String): List<FlutterMediaOverlay>? {
        val document = GuidedNavigationDocument.fromJSON(jsonString) ?: return null
        return document
            .toMediaOverlays()
            .mapNotNull { overlay ->
                val textFile = overlay.items.firstOrNull()?.textFile ?: return@mapNotNull null
                val roEntry =
                    sourcePublication.readingOrder.withIndex().firstOrNull { (_, roLink) ->
                        Url
                            .invoke(textFile)
                            ?.let { roLink.href.resolve().isEquivalent(it) } == true
                    }
                val position = (roEntry?.index ?: -1) + 1
                val duration = roEntry?.value?.duration ?: 0.0
                overlay.copy(
                    items =
                        overlay.items.map { item ->
                            item.copy(position = position, readingOrderItemDuration = duration)
                        },
                )
            }.ifEmpty { null }
    }
}

