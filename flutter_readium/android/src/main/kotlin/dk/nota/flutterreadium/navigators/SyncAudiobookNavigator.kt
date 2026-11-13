package dk.nota.flutterreadium.navigators

import android.os.Bundle
import dk.nota.flutterreadium.FlutterAudioPreferences
import dk.nota.flutterreadium.OrderedLocatorEmitter
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.ReadiumReader
import dk.nota.flutterreadium.XhtmlIdTree
import dk.nota.flutterreadium.cleanHref
import dk.nota.flutterreadium.copyWithTimeFragment
import dk.nota.flutterreadium.findReadingOrderLink
import dk.nota.flutterreadium.getReadingOrderItemDuration
import dk.nota.flutterreadium.makeSyncAudiobook
import dk.nota.flutterreadium.getTextId
import dk.nota.flutterreadium.SyncTimelineStore
import dk.nota.flutterreadium.models.FlutterMediaOverlay
import dk.nota.flutterreadium.progression
import dk.nota.flutterreadium.timeWithDuration
import dk.nota.flutterreadium.tocHref
import dk.nota.flutterreadium.xhtmlIdTree
import dk.nota.flutterreadium.withMainContext
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.util.Url
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

private const val TAG = "SyncAudiobookNavigator"

private const val SYNC_AUDIO_DECORATION_ID_UTTERANCE = "synced-utterance"

@OptIn(ExperimentalCoroutinesApi::class, ExperimentalReadiumApi::class)
class SyncAudiobookNavigator internal constructor(
    publication: Publication,
    /**
     * The media overlays for the current publication, if any. These are used to map between the audio narration and the text
     */
    private var mediaOverlays: List<FlutterMediaOverlay?>,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    preferences: FlutterAudioPreferences,
    /**
     * Lazy timeline store when playback is streamed; null keeps the eager (fully parsed)
     * overlay list, i.e. today's behavior including the process-death restore path.
     */
    private val store: SyncTimelineStore? = null,
) : AudiobookNavigator(publication, timebasedListener, initialLocator, preferences) {
    init {
        // We need to translate the epub based locator to an audio based locator
        this.initialLocator =
            initialLocator?.let { locator -> mapTextLocatorToMediaOverlayLocator(locator) }
    }

    private var pendingTextInitialLocator = initialLocator

    override suspend fun initNavigator() {
        pendingTextInitialLocator?.let { pending ->
            initialLocator = anchorUncuedTextLocator(pending)?.let { mapTextLocatorToMediaOverlayLocator(it) }
            pendingTextInitialLocator = null
        }
        super.initNavigator()
    }

    val decorationGroup = "sync-audio"

    private val locatorEmitter =
        OrderedLocatorEmitter(
            enrich = { ReadiumReader.epubEnrichLocatorWithTocHref(it) },
            onLocator = { locator, link -> timebaseListener.onTimebasedCurrentLocatorChanges(locator, link) },
        )

    /** Parsed XHTML id trees by resource, null when a resource could not be read. */
    private val xhtmlIdTrees = mutableMapOf<Url, XhtmlIdTree?>()

    /**
     * In-flight/serialized window extension. [extending] mutes cue mapping while the old player
     * is being replaced; [extension] lets the ended-edge takeover join the same attempt.
     */
    private var extending = false
    private var extension: Deferred<Boolean>? = null

    /** Cue count of the overlay list the current navigator was built from. */
    private val loadedCues: Int
        get() = mediaOverlays.sumOf { it?.items?.size ?: 0 }

    /**
     * Lookahead driver, called from the periodic locator flow: when less than
     * [SyncTimelineStore.LOOKAHEAD_MARGIN_SECONDS] remain on the current track and segments are
     * still loadable, fetch ahead and extend the window.
     */
    private fun maybeExtendWindow(
        locator: Locator,
        trackDuration: Duration?,
        timeOffset: Duration,
    ) {
        val store = store ?: return
        if (isNavigatorDisposed || extending || extension != null) return
        // Paused ticks must not churn the window (the web mapper driver only runs during
        // playback); rebuilds while paused race paused seeks. The edge takeover covers
        // a playhead that reaches the loaded tail.
        val pb = audioNavigator?.playback?.value ?: return
        if (!pb.playWhenReady || pb.state is AudioNavigator.State.Ended) return
        // Guard from the PLAYHEAD's segment: after a backward seek the loaded tail sits
        // ahead, and a tail-based check would disable lookahead while fillAhead still
        // fills from the playhead.
        val playhead = store.roIndexForAudio(locator.href.toString()) ?: store.loadedTailIndex()
        if (store.nextLoadableSegment(playhead + 1) == null) return
        val remaining = trackDuration?.minus(timeOffset) ?: return
        if (remaining > SyncTimelineStore.LOOKAHEAD_MARGIN_SECONDS.seconds) return
        PluginLog.d(
            TAG,
            "::maybeExtendWindow - ${remaining.inWholeSeconds}s left on ${locator.href}; extending window",
        )
        extendWindow()
    }

    /** Starts (or joins) the serialized window extension. */
    private fun extendWindow(): Deferred<Boolean> {
        extension?.let { return it }
        val attempt = async { runWindowExtension() }
        extension = attempt
        attempt.invokeOnCompletion { if (extension === attempt) extension = null }
        return attempt
    }

    /**
     * Loads segments past the playhead one at a time, advancing past slots at the failure
     * cap, until new cues land - the K-ahead budget may stop on exhausted slots while a
     * healthy segment waits beyond them (ADR 0003 "honest end"). Then swaps in the wider
     * pseudo publication and rebuilds the player at the current audio locator (the same
     * teardown + media-session reopen sequence the stream-recovery rebuild runs). Cue
     * mapping is muted only across the swap, not during the fetch.
     */
    private suspend fun runWindowExtension(): Boolean {
        val store = store ?: return false
        if (isNavigatorDisposed || extending) return false
        var cursor =
            store.roIndexForAudio(audioNavigator?.currentLocator?.value?.href?.toString())
                ?: store.loadedTailIndex()
        while (!isNavigatorDisposed && store.loadedCueCount() <= loadedCues) {
            val next = store.nextLoadableSegment(cursor + 1) ?: break
            store.loadSegment(next)
            // Retry an unsettled slot in place; advance only past a settled one.
            if (store.isSettled(next)) cursor = next
        }

        val (pseudoPublication, overlays) = store.sourcePublication.makeSyncAudiobook(store)
        val cues = overlays?.sumOf { it?.items?.size ?: 0 } ?: 0
        if (overlays == null || cues <= loadedCues) return false

        val wasPlaying = audioNavigator?.playback?.value?.playWhenReady ?: false
        val previousPublication = publication
        val previousOverlays = mediaOverlays
        publication = pseudoPublication
        mediaOverlays = overlays
        extending = true
        // Read the resume position across the swap only: the fetch above ran unmuted,
        // so playback never rewinds by the fetch duration.
        val current =
            audioNavigator?.currentLocator?.value
                ?: state[CURRENT_TIMEBASE_LOCATOR_KEY] as? Locator
        try {
            val rebuilt =
                rebuildNavigator(current) ?: run {
                    // Keep the overlay list aligned with the player the navigator actually has:
                    // an extended list on a torn-down player maps cues to tracks that are gone.
                    publication = previousPublication
                    mediaOverlays = previousOverlays
                    PluginLog.w(TAG, "::runWindowExtension - rebuild failed with $cues cues; surfacing the edge instead")
                    return false
                }
            if (wasPlaying) {
                withMainContext { rebuilt.play() }
            }
            PluginLog.d(
                TAG,
                "::runWindowExtension - window extended to $cues cues / ${overlays.size} overlays " +
                    "(tail segment ${store.loadedTailIndex()})",
            )
            ReadiumReader.onSyncTimelineWindowExtended(
                store.totalDurationSecs(),
                pseudoPublication.readingOrder.map { it.duration },
            )
            return true
        } finally {
            extending = false
        }
    }

    override val takesOverAtEdge: Boolean
        get() = store != null

    /**
     * End of the last known track. Extends the window and rebuilds while more segments are
     * loadable (true = the ended emission stays suppressed); false is the honest end - nothing
     * loadable remains, or every load failed - which reaches clients like the eager path does.
     */
    override suspend fun takeOverAtEdge(): Boolean {
        if (store == null || isNavigatorDisposed) return false
        return extendWindow().await()
    }

    /**
     * Seek/goTo beyond the loaded window: fetch the segment covering [href] so cue mapping can
     * resolve it, and widen the playlist when the target track is not in it yet. Bounded loop:
     * a joined lookahead may have snapshotted the window before this fetch landed; the next
     * pass extends again until the live list carries the target's cues.
     */
    private suspend fun ensureWindowFor(href: String?) {
        val store = store ?: return
        for (attempt in 0 until 3) {
            extension?.await()
            store.ensureSegmentForText(href)
            if (store.loadedCueCount() <= loadedCues) return
            extendWindow().await()
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator
        if (navigator == null) {
            PluginLog.e(TAG, "::setupNavigatorListeners - navigator is null")
            return
        }

        super.setupNavigatorListeners()
        navigator.currentLocator
            .map { locator ->
                val duration = publication.getReadingOrderItemDuration(locator.href)
                val timeOffset = locator.locations.timeWithDuration(duration) ?: 0.seconds
                maybeExtendWindow(locator, duration, timeOffset)
                // Mid window-extension: the outgoing player's trailing ticks must not emit
                // cues mapped from the not-yet-swapped overlay list.
                if (extending) return@map null
                mediaOverlays
                    .firstNotNullOfOrNull {
                        it?.findItemInRange(
                            locator.href,
                            timeOffset,
                        )
                    }?.takeIf { it.syncTextLocator != null }
                    ?.let { mediaOverlay ->
                        PluginLog.d(
                            TAG,
                            "::setupNavigatorListeners - syncTextLocator $timeOffset, locator:${mediaOverlay.syncTextLocator}",
                        )
                        Pair(mediaOverlay, mediaOverlay.syncTextLocator!!)
                    }
            }.filterNotNull()
            .distinctUntilChangedBy { (_, locator) -> locator.href.toString() + locator.locations.cssSelector }
            .onEach { (mediaOverlay, textLocator) ->
                ReadiumReader.epubSyncToLocator(textLocator, false, mediaOverlay.duration)

                decorateCurrentUtterance(textLocator)
            }.launchIn(this)
            .let { jobs.add(it) }
    }

    @OptIn(InternalReadiumApi::class)
    override fun onCurrentLocatorChanges(locator: Locator) {
        // Mid window-extension: the outgoing player's locators must not reach clients; the
        // rebuilt navigator re-emits the position.
        if (extending) return
        val readingOrderLink = publication.findReadingOrderLink(locator.href)

        val duration = publication.getReadingOrderItemDuration(locator.href)
        val timeOffset = locator.locations.timeWithDuration(duration)

        val mediaOverlay =
            timeOffset?.let { timeOffset ->
                mediaOverlays.firstNotNullOfOrNull {
                    it?.findItemInRange(
                        locator.href,
                        timeOffset,
                    )
                }
            } ?: run {
                PluginLog.d(
                    TAG,
                    "::onCurrentLocatorChanges - no media-overlay item found for locator=$locator, timeOffset=$timeOffset",
                )
                return
            }

        // Get the flutter audio locator from the media-overlay and enrich it with progression
        // total progression from the player's locator.
        val audioLocator =
            mediaOverlay.flutterAudioLocator?.let { fal ->
                fal.copy(
                    locations =
                        fal.locations.copy(
                            fragments = locator.locations.fragments,
                            progression = locator.locations.progression,
                            // The player's totalProgression is relative to the pseudo publication,
                            // which under streaming is only the loaded window; the store knows the
                            // book. Fall back to the player value on the eager path.
                            totalProgression =
                                store?.locatorProgression(
                                    locator.href.toString(),
                                    timeOffset?.inWholeMilliseconds?.let { it / 1000.0 },
                                ) ?: locator.locations.totalProgression,
                        ),
                )
            }

        if (audioLocator == null) {
            PluginLog.d(TAG, "::onCurrentLocatorChanges - couldn't resolve $locator to audio-locator")

            return
        }

        // Enrichment suspends; preserve cue order even when a later cue already has its owner.
        launch { locatorEmitter.emit(audioLocator, readingOrderLink) }
    }

    override fun storeState(): Bundle {
        // We don't add media-overlays to the state, because they are always restored from the
        // ReadiumReader.currentPublication.
        return super.storeState()
    }

    override suspend fun play(fromLocator: Locator?) {
        if (fromLocator == null) {
            return super.play(fromLocator)
        }

        ensureWindowFor(fromLocator.href.toString())
        val audioLocator = anchorUncuedTextLocator(fromLocator)?.let { mapTextLocatorToMediaOverlayLocator(it) }
        if (audioLocator != null) {
            super.play(audioLocator)
        } else {
            PluginLog.d(TAG, "::play: no audio locator found for $fromLocator")
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        seekToLocator(locator)
    }

    suspend fun seekToLocator(locator: Locator): Boolean {
        ensureWindowFor(locator.href.toString())
        val audioLocator =
            anchorUncuedTextLocator(locator)?.let { mapTextLocatorToMediaOverlayLocator(it) } ?: run {
                PluginLog.d(TAG, "::seekToLocator - no audio locator found for $locator")
                return false
            }
        super.goToLocator(audioLocator)
        return true
    }

    /** Resolve XHTML targets before same-file fallback guards; seeking does not assign ownership. */
    private suspend fun anchorUncuedTextLocator(locator: Locator): Locator? {
        val href = locator.href
        val textId = locator.getTextId() ?: return locator
        val known =
            mediaOverlays.any { mo ->
                mo?.findItemFromTextId(href, textId) != null || mo?.findItemFromTocHref(href, textId) != null
            }
        if (known) return locator

        val path = href.cleanHref()
        val tree =
            if (xhtmlIdTrees.containsKey(path)) {
                xhtmlIdTrees[path]
            } else {
                publication.xhtmlIdTree(path).also { xhtmlIdTrees[path] = it }
            }
        val cueIds =
            mediaOverlays
                .flatMap { it?.items.orEmpty() }
                .filter { item -> Url.invoke(item.textFile)?.let { path.isEquivalent(it) } == true }
                .map { it.textId }
                .toSet()
        if (tree == null) return locator
        return tree.anchor(locator, textId, cueIds)
    }

    private suspend fun decorateCurrentUtterance(uttLocator: Locator) {
        val decorations = mutableListOf<Decoration>()
        val utteranceStyle = ReadiumReader.decorationStyle.utteranceStyle
        utteranceStyle?.let { style ->
            decorations.add(
                Decoration(
                    id = SYNC_AUDIO_DECORATION_ID_UTTERANCE,
                    locator = uttLocator,
                    style = style,
                ),
            )
        }

        ReadiumReader.applyDecorations(decorations, group = decorationGroup)
    }

    /**
     * Called when decorations (e.g., highlights) need to be updated.
     */
    suspend fun decorationsUpdated() {
        val navigator =
            audioNavigator ?: run {
                PluginLog.d(TAG, "::decorationsUpdated - navigator is null")
                return
            }

        val locator = navigator.currentLocator.value
        val textLocator =
            mediaOverlays
                .firstNotNullOfOrNull { mo ->
                    mo?.findItemFromLocator(locator)
                }?.syncTextLocator ?: run {
                PluginLog.d(TAG, "::decorationsUpdated - didn't find a current text locator")
                return
            }

        decorateCurrentUtterance(textLocator)
    }

    override fun onEnded() {
        launch {
            ReadiumReader.applyDecorations(listOf(), group = decorationGroup)
        }
    }

    @OptIn(InternalReadiumApi::class)
    private fun mapTextLocatorToMediaOverlayLocator(locator: Locator): Locator? {
        // Only allow the imprecise resource-first fallback when navigating into a
        // *different* resource than the one currently playing — an uncued anchor
        // within the current chapter must not rewind audio. See issue #139.
        val curAudioLoc = audioNavigator?.currentLocator?.value
        val curTextFile: String? =
            if (curAudioLoc != null) {
                val duration = publication.getReadingOrderItemDuration(curAudioLoc.href)
                val timeOffset = curAudioLoc.locations.timeWithDuration(duration) ?: 0.seconds
                mediaOverlays.firstNotNullOfOrNull { mo -> mo?.findItemInRange(curAudioLoc.href, timeOffset) }?.textFile
            } else {
                null
            }
        val crossResource = curTextFile == null || curTextFile != locator.href.path

        val mediaOverlay =
            mediaOverlays.firstNotNullOfOrNull { mo ->
                mo?.findItemFromLocator(locator, allowResourceFallback = crossResource)
            }

        val syncAudioLocator =
            mediaOverlay?.skipToAudioLocator ?: run {
                PluginLog.w(
                    TAG,
                    "::mapTextLocatorToMediaOverlayLocator couldn't resolve $locator to a media overlay with an audio locator",
                )
                return null
            }

        val timeOffsetFromProgression =
            locator.progression
                ?.let { progression -> mediaOverlay.readingOrderItemDuration * progression }
                ?.seconds
        val timeOffsetFromFragment =
            locator.locations.time

        if (timeOffsetFromProgression == null && timeOffsetFromFragment == null) {
            PluginLog.d(
                TAG,
                "::mapTextLocatorToMediaOverlayLocator couldn't find time offset from $locator, return $syncAudioLocator",
            )
            return syncAudioLocator
        }

        if (timeOffsetFromProgression != null && timeOffsetFromFragment != null && timeOffsetFromProgression != timeOffsetFromFragment) {
            PluginLog.d(
                TAG,
                "::mapTextLocatorToMediaOverlayLocator - time offset from both progression $timeOffsetFromProgression and time fragment $timeOffsetFromFragment but they differ",
            )
        }

        val timeOffset = timeOffsetFromProgression ?: timeOffsetFromFragment ?: Duration.ZERO

        val updateSyncAudioLocator = syncAudioLocator.copyWithTimeFragment(timeOffset)

        PluginLog.d(TAG, "::mapTextLocatorToMediaOverlayLocator - $locator to $updateSyncAudioLocator")
        return updateSyncAudioLocator
    }

    override fun dispose() {
        store?.cancelPending()
        launch {
            ReadiumReader.applyDecorations(listOf(), group = decorationGroup)
        }

        super.dispose()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            mediaOverlays: List<FlutterMediaOverlay?>,
            timebasedListener: TimebasedListener,
            state: Bundle,
        ): SyncAudiobookNavigator {
            val initialLocator =
                state
                    .getString(CURRENT_TIMEBASE_LOCATOR_KEY)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences =
                state
                    .getString(AUDIO_PREFERENCES_KEY)
                    ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                    ?: FlutterAudioPreferences()

            return SyncAudiobookNavigator(
                publication,
                mediaOverlays,
                timebasedListener,
                initialLocator,
                preferences,
            )
        }
    }
}
