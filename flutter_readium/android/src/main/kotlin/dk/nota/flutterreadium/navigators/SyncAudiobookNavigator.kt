package dk.nota.flutterreadium.navigators

import android.os.Bundle
import dk.nota.flutterreadium.FlutterAudioPreferences
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.ReadiumReader
import dk.nota.flutterreadium.XhtmlIdTree
import dk.nota.flutterreadium.cleanHref
import dk.nota.flutterreadium.copyWithTimeFragment
import dk.nota.flutterreadium.findReadingOrderLink
import dk.nota.flutterreadium.getReadingOrderItemDuration
import dk.nota.flutterreadium.getTextId
import dk.nota.flutterreadium.models.FlutterMediaOverlay
import dk.nota.flutterreadium.progression
import dk.nota.flutterreadium.timeWithDuration
import dk.nota.flutterreadium.tocHref
import dk.nota.flutterreadium.xhtmlIdTree
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
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
class SyncAudiobookNavigator(
    publication: Publication,
    /**
     * The media overlays for the current publication, if any. These are used to map between the audio narration and the text
     */
    private val mediaOverlays: List<FlutterMediaOverlay?>,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    preferences: FlutterAudioPreferences,
) : AudiobookNavigator(publication, timebasedListener, initialLocator, preferences) {
    init {
        // We need to translate the epub based locator to an audio based locator
        this.initialLocator =
            initialLocator?.let { locator -> mapTextLocatorToMediaOverlayLocator(locator) }
    }

    val decorationGroup = "sync-audio"

    private val locatorEmitMutex = Mutex()

    /** Parsed XHTML id trees by resource, null when a resource could not be read. */
    private val xhtmlIdTrees = mutableMapOf<Url, XhtmlIdTree?>()

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
                            totalProgression = locator.locations.totalProgression,
                        ),
                )
            }

        if (audioLocator == null) {
            PluginLog.d(TAG, "::onCurrentLocatorChanges - couldn't resolve $locator to audio-locator")

            return
        }

        // A cue the narration nesting gives no ToC owner (e.g. inside a newspaper <section>) gets
        // one from document order. The lookup suspends, so the lock keeps emissions in order.
        launch {
            locatorEmitMutex.withLock {
                val emittingLocator =
                    if (audioLocator.locations.tocHref == null && audioLocator.locations.cssSelector != null) {
                        ReadiumReader.epubEnrichLocatorWithTocHref(audioLocator)
                    } else {
                        audioLocator
                    }
                // NOTE: Important, don't call base classes here, as they will trigger incorrect values for
                // readingOrderLink
                timebaseListener.onTimebasedCurrentLocatorChanges(emittingLocator, readingOrderLink)
            }
        }
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

        val audioLocator = mapTextLocatorToMediaOverlayLocator(anchorUncuedTextLocator(fromLocator))
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
        val audioLocator =
            mapTextLocatorToMediaOverlayLocator(anchorUncuedTextLocator(locator)) ?: run {
                PluginLog.d(TAG, "::seekToLocator - no audio locator found for $locator")
                return false
            }
        super.goToLocator(audioLocator)
        return true
    }

    /**
     * Point a text locator at the first cue inside its element when the element is neither a cue
     * nor a known ToC anchor (e.g. a newspaper `<section>` absent from the narration). Without
     * this, seeking to one inside the playing resource fails (#139 forbids the resource fallback
     * there). See ADR 0001.
     */
    private suspend fun anchorUncuedTextLocator(locator: Locator): Locator {
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
        val first = tree?.firstDescendant(textId, cueIds) ?: return locator

        PluginLog.d(TAG, "::anchorUncuedTextLocator - $href#$textId -> #$first")
        return locator.copy(
            locations =
                locator.locations.copy(
                    fragments = listOf(first),
                    otherLocations = locator.locations.otherLocations + ("cssSelector" to "#$first"),
                ),
        )
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
