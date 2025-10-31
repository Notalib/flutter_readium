package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.copyWithTimeFragment
import dk.nota.flutter_readium.getTimeOffset
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.models.FlutterMediaOverlay
import dk.nota.flutter_readium.models.FlutterMediaOverlayItem
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "SyncAudiobookNavigator"

private const val mediaOverlaysKey = "MediaOverlays"

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

    private var lastMediaOverlayItem: FlutterMediaOverlayItem? = null

    override fun onCurrentLocatorChanges(locator: Locator) {
        val readingOrderLink =
            publication.readingOrder.find { link ->
                link.href.toString() == locator.href.toString()
            }

        val duration = readingOrderLink?.duration
        val timeOffset = locator.getTimeOffset() ?: (duration?.let { duration ->
            locator.locations.progression?.let { prog -> duration * prog }
        })

        val mediaOverlay = mediaOverlays.firstNotNullOfOrNull {
            it?.findItemInRange(
                locator.href,
                timeOffset ?: 0.0
            )
        }

        if (mediaOverlay == null) {
            Log.d(
                TAG,
                ":onTimebasedCurrentLocatorChanges no mo item found for locator=$locator, timeOffset=$timeOffset"
            )
            return
        }

        if (mediaOverlay != lastMediaOverlayItem) {
            // MediaOverlayItem changed, notify EPUB reader to navigate to element and decorate it.
            mediaOverlay.syncTextLocator?.let { textLocator ->
                mainScope.async {
                    // IMPORTANT: We use epubGoToLocator here, NOT goToLocator, as the latter
                    // triggers an infinite loop
                    ReadiumReader.epubGoToLocator(textLocator, false)

                    decorateCurrentUtterance(textLocator)
                }
            }

            lastMediaOverlayItem = mediaOverlay
        }

        // Get the flutter audio locator from the media-overlay and enrich it with progression
        // total progression from the player's locator.
        val audioLocator = mediaOverlay.flutterAudioLocator?.let { fal ->
            fal.copy(
                locations = fal.locations.copy(
                    fragments = locator.locations.fragments,
                    progression = locator.locations.progression,
                    totalProgression = locator.locations.totalProgression,
                )
            )
        }

        if (audioLocator == null) {
            Log.d(TAG, "::Couldn't resolve currentLocator $locator to audio-locator")

            return
        }

        super.onCurrentLocatorChanges(audioLocator)
    }

    override fun storeState(): Bundle {
        return super.storeState().apply {
            putSerializable(mediaOverlaysKey, ArrayList(mediaOverlays))
        }
    }

    override suspend fun play(fromLocator: Locator?) {
        if (fromLocator == null) {
            return super.play(fromLocator)
        }

        val audioLocator = mapTextLocatorToMediaOverlayLocator(fromLocator)
        if (audioLocator != null) {
            super.play(audioLocator)
        } else {
            Log.d(TAG, "goToLocator: no audio locator found for $fromLocator")
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
                )
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
            Log.d(TAG, ":setDecorationStyle: navigator is null")
            return
        }

        val locator = navigator.currentLocator.value
        val textLocator = mediaOverlays.firstNotNullOfOrNull { mo ->
            mo?.findItemFromLocator(locator)
        }?.syncTextLocator ?: return
        mainScope.async {
            decorateCurrentUtterance(textLocator)
        }.await()
    }

    private fun mapTextLocatorToMediaOverlayLocator(locator: Locator): Locator? {
        val newLocator = mediaOverlays.firstNotNullOfOrNull { mo ->
            mo?.findItemFromLocator(locator)
        }?.skipToAudioLocator ?: return null

        return letIfBothNotNull(newLocator, locator.getTimeOffset())?.let { (nl, timeOffset) ->
            nl.copyWithTimeFragment(timeOffset)
        } ?: newLocator
    }

    companion object {
        fun restoreState(
            publication: Publication,
            mediaOverlays: List<FlutterMediaOverlay?>,
            listener: TimebasedListener,
            state: Bundle
        ): SyncAudiobookNavigator {
            val locator = state.getString(currentTimebaseLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(audioPreferencesKey)
                ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                ?: FlutterAudioPreferences()

            return SyncAudiobookNavigator(
                publication,
                mediaOverlays,
                listener,
                locator,
                preferences
            )
        }
    }
}
