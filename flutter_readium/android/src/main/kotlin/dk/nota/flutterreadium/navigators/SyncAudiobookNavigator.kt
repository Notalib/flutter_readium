package dk.nota.flutterreadium.navigators

import android.os.Bundle
import dk.nota.flutterreadium.FlutterAudioPreferences
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.ReadiumReader
import dk.nota.flutterreadium.copyWithTimeFragment
import dk.nota.flutterreadium.findReadingOrderLink
import dk.nota.flutterreadium.getReadingOrderItemDuration
import dk.nota.flutterreadium.models.FlutterMediaOverlay
import dk.nota.flutterreadium.progression
import dk.nota.flutterreadium.timeWithDuration
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
            PluginLog.d(TAG, "::play: no audio locator found for $fromLocator")
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        val audioLocator = mapTextLocatorToMediaOverlayLocator(locator)
        if (audioLocator != null) {
            super.goToLocator(audioLocator)
        } else {
            PluginLog.d(TAG, "::goToLocator - no audio locator found for $locator")
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
        val mediaOverlay =
            mediaOverlays.firstNotNullOfOrNull { mo ->
                mo?.findItemFromLocator(locator)
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
