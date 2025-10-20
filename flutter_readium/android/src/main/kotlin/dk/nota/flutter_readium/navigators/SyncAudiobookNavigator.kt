package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.getTimeOffset
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
    val decorationGroup = "sync-audio"

    private var lastMediaOverlayItem: FlutterMediaOverlayItem? = null

    override suspend fun initNavigator() {
        // We need to translate the epub based locator to an audio based locator
        this.initialLocator = this.initialLocator?.let { locator ->
            mediaOverlays.firstNotNullOfOrNull { mo ->
                mo?.findItemFromLocator(locator)
            }?.skipToAudioLocator ?: initialLocator
        }

        super.initNavigator()
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        var audioLocator: Locator
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
                locator.href.toString(),
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
            mediaOverlay.textLocator?.let { textLocator ->
                mainScope.async {
                    // IMPORTANT: We use epubGoToLocator here, NOT goToLocator, as the latter
                    // triggers an infinite loop
                    ReadiumReader.epubGoToLocator(textLocator, false)

                    decorateCurrentUtterance(textLocator)
                }
            }

            lastMediaOverlayItem = mediaOverlay
        }

        audioLocator = mediaOverlay.audioLocator ?: locator

        super.onCurrentLocatorChanges(audioLocator)
    }

    override fun storeState(): Bundle {
        return super.storeState().apply {
            putSerializable(mediaOverlaysKey, ArrayList(mediaOverlays))
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        val audioLocator = mediaOverlays.firstNotNullOfOrNull { mo ->
            mo?.findItemFromLocator(locator)
        }?.skipToAudioLocator

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
        }?.textLocator ?: return
        mainScope.async {
            decorateCurrentUtterance(textLocator)
        }.await()
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
