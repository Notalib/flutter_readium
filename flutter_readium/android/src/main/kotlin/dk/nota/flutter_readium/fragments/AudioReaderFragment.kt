package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.models.AudioReaderViewModel
import dk.nota.flutter_readium.viewLifecycle
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferencesEditor
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.navigator.media.audio.AudioNavigatorFactory.Companion.invoke
import org.readium.navigator.media.common.TimeBasedMediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.mediatype.MediaType.Companion.MP3

private const val TAG = "AudioReaderFragment"
private const val exoPlayerPreferencesKeyName = "ExoPlayerPreferences"

private var instanceNo = 0

@OptIn(ExperimentalReadiumApi::class)
public class AudioReaderFragment : BaseReaderFragment() {

    private val instance = ++instanceNo

    private val audioVm: AudioReaderViewModel
        get() {
            return vm as AudioReaderViewModel
        }

    private val audioNavigator: AudioNavigator<*, *>
        get() {
            return navigator as AudioNavigator<*, *>
        }

    private var editor: ExoPlayerPreferencesEditor? = null;

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            Log.d(
                TAG,
                "::onCreate $instance - savedInstanceState? = ${savedInstanceState != null} "
            )

            if (savedInstanceState != null) {
                vm = restoreViewModelFromState(savedInstanceState)
            }

            // TODO: Handle vm == null and error cases.

            // Create AudioNavigatorFactory
            val navigatorFactory = AudioNavigatorFactory(
                vm?.publication!!,
                ExoPlayerEngineProvider(requireActivity().application)
            )

            lifecycleScope.launch {
                navigator = navigatorFactory!!.createNavigator(
                    vm?.locator,
                    audioVm.preferences
                ).getOrNull()!!

                editor = navigatorFactory.createAudioPreferencesEditor(audioVm.preferences!!)

                audioNavigator.playback
                    .onEach { onPlaybackChanged(it) }
                    .launchIn(viewLifecycleOwner.lifecycleScope)
            }

        } finally {
            Log.d(TAG, "::onCreate $instance - ended")
        }
    }

    fun onPlaybackChanged(pb: AudioNavigator.Playback) {
        Log.d(TAG, "::onPlaybackChanged $pb")

        // Create locator from Playback

        var position = pb.index
        var currentItem = audioNavigator.readingOrder.items[position]
        var pubCurrentItem = audioVm.publication?.readingOrder[position]
        var chapterTitle = pubCurrentItem?.title
        var chapterDuration = currentItem.duration
        var chapterOffset = pb.offset
        var chapterOffsetSeconds = chapterOffset.inWholeSeconds
        var chapterProgression =
            chapterOffset.inWholeMilliseconds / chapterDuration!!.inWholeMilliseconds

        // TODO: calculate totalProgression and add to Locations.
        var totalDuration = audioNavigator.readingOrder.duration
        var currentTotalOffset = audioNavigator.readingOrder.items.slice(0..position - 1)
            .sumOf { it.duration?.inWholeMilliseconds ?: 0 } + chapterOffset.inWholeMilliseconds
        var totalProgression = currentTotalOffset / (totalDuration?.inWholeMilliseconds ?: 1)

        var locations = Locator.Locations(
            arrayOf("t=${chapterOffsetSeconds}").toList(),
            progression = chapterProgression.toDouble(),
            position,
            totalProgression = totalProgression.toDouble()
        )
        var locator = Locator(currentItem.href, pubCurrentItem?.mediaType ?: MP3, chapterTitle, locations)
        // Submit Locator to flutter channel
    }

    override fun storeViewModelInState(outState: Bundle) {
        super.storeViewModelInState(outState)

        editor?.preferences?.let {
            val jsonString = Json.encodeToString(it)
            outState.putString(exoPlayerPreferencesKeyName, jsonString)
            val model = vm as AudioReaderViewModel
            model.preferences = it
        }
    }

    override fun restoreViewModelFromState(savedInstanceState: Bundle): AudioReaderViewModel? {
        val restoredPreferences = savedInstanceState.getString(exoPlayerPreferencesKeyName)
            ?.let { Json.decodeFromString(it) as ExoPlayerPreferences } ?: ExoPlayerPreferences()

        return super.restoreViewModelFromState(savedInstanceState)?.let {
            val vm = AudioReaderViewModel().apply()
            {
                identifier = it.identifier
                pubUrl = it.pubUrl
                publication = it.publication
                locator = it.locator
                preferences = restoredPreferences
            }

            return vm
        }
    }
}
