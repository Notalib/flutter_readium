package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.copyWithTimeFragment
import dk.nota.flutter_readium.findReadingOrderLink
import dk.nota.flutter_readium.getReadingOrderItemDuration
import dk.nota.flutter_readium.models.FlutterMediaOverlay
import dk.nota.flutter_readium.progression
import dk.nota.flutter_readium.timeWithDuration
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.extensions.time
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
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

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator
        if (navigator == null) {
            Log.e(TAG, ": setupNavigatorListeners - navigator is null")
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
                        Log.d(
                            TAG,
                            ":syncTexLocator $timeOffset, locator:$mediaOverlay.syncTextLocator",
                        )
                        Pair(mediaOverlay, mediaOverlay.syncTextLocator!!)
                    }
            }.filterNotNull()
            .distinctUntilChangedBy { (_, locator) -> locator.href.toString() + locator.locations.cssSelector }
            .onEach { (mediaOverlay, textLocator) ->
                ReadiumReader.epubSyncToLocator(textLocator, false, mediaOverlay.duration)

                decorateCurrentUtterance(textLocator)
            }.launchIn(mainScope)
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
                Log.d(
                    TAG,
                    ":onCurrentLocatorChanges no media-overlay item found for locator=$locator, timeOffset=$timeOffset",
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
            Log.d(TAG, "::Couldn't resolve currentLocator $locator to audio-locator")

            return
        }

        // NOTE: Important, don't call base classes here, as they will trigger incorrect values for
        // readingOrderLink
        timebaseListener.onTimebasedCurrentLocatorChanges(audioLocator, readingOrderLink)
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

        val audioLocator = mapTextLocatorToMediaOverlayLocator(fromLocator)
        if (audioLocator != null) {
            super.play(audioLocator)
        } else {
            Log.d(TAG, "::play: no audio locator found for $fromLocator")
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        val audioLocator = mapTextLocatorToMediaOverlayLocator(locator)
        if (audioLocator != null) {
            super.goToLocator(audioLocator)
        } else {
            Log.d(TAG, "goToLocator: no audio locator found for $locator")
        }
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
        val navigator = audioNavigator
        if (navigator == null) {
            Log.d(TAG, ":decorationsUpdated: navigator is null")
            return
        }

        val locator = navigator.currentLocator.value
        val textLocator =
            mediaOverlays
                .firstNotNullOfOrNull { mo ->
                    mo?.findItemFromLocator(locator)
                }?.syncTextLocator ?: run {
                Log.d(TAG, ":decorationsUpdated - didn't find a current text locator")
                return
            }

        decorateCurrentUtterance(textLocator)
    }

    override fun onEnded() {
        mainScope.launch {
            ReadiumReader.applyDecorations(listOf(), group = decorationGroup)
        }
    }

    @OptIn(InternalReadiumApi::class)
    private fun mapTextLocatorToMediaOverlayLocator(locator: Locator): Locator? {
        val mediaOverlay =
            mediaOverlays.firstNotNullOfOrNull { mo ->
                mo?.findItemFromLocator(locator)
            }

        val syncAudioLocator =
            mediaOverlay?.skipToAudioLocator ?: run {
                Log.e(
                    TAG,
                    "::mapTextLocatorToMediaOverlayLocator couldn't resolve $locator to a media overlay with an audio locator",
                )
                return null
            }

        val timeOffsetFromProgression =
            locator.progression
                ?.let { progression -> mediaOverlay.readingOrderItemDuration * progression }
                ?.toInt()
        val timeOffsetFromFragment =
            locator.locations.time
                ?.inWholeSeconds
                ?.toInt()

        if (timeOffsetFromProgression == null && timeOffsetFromFragment == null) {
            Log.d(
                TAG,
                "::mapTextLocatorToMediaOverlayLocator couldn't find time offset from $locator, return $syncAudioLocator",
            )
            return syncAudioLocator
        }

        if (timeOffsetFromProgression != null && timeOffsetFromFragment != null && timeOffsetFromProgression != timeOffsetFromFragment) {
            Log.d(
                TAG,
                "::mapTextLocatorToMediaOverlayLocator - time offset from both progression $timeOffsetFromProgression and time fragment $timeOffsetFromFragment but they differ",
            )
        }

        val timeOffset = timeOffsetFromProgression ?: timeOffsetFromFragment ?: 0

        val updateSyncAudioLocator = syncAudioLocator.copyWithTimeFragment(timeOffset)

        Log.d(TAG, "::mapTextLocatorToMediaOverlayLocator - $locator to $updateSyncAudioLocator")
        return updateSyncAudioLocator
    }

    override fun dispose() {
        mainScope.launch {
            ReadiumReader.applyDecorations(listOf(), group = decorationGroup)
        }

        super.dispose()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            mediaOverlays: List<FlutterMediaOverlay?>,
            listener: TimebasedListener,
            state: Bundle,
        ): SyncAudiobookNavigator {
            val locator =
                state
                    .getString(currentTimebaseLocatorKey)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences =
                state
                    .getString(audioPreferencesKey)
                    ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                    ?: FlutterAudioPreferences()

            return SyncAudiobookNavigator(
                publication,
                mediaOverlays,
                listener,
                locator,
                preferences,
            )
        }
    }
}
