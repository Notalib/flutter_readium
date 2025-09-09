package dk.nota.flutter_readium.navigators

import android.util.Log
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferencesEditor
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType.Companion.MP3
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "AudioNavigator"

@OptIn(ExperimentalReadiumApi::class)
class AudioNavigator(
    private val publication: Publication,
    private val initialLocator: Locator?,
    private var preferences: ExoPlayerPreferences = ExoPlayerPreferences()
) : Navigator {
    private val jobs = mutableListOf<Job>()

    private var audioNavigator: AudioNavigator<*, *>? = null
    private var editor: ExoPlayerPreferencesEditor? = null

    override suspend fun initNavigator() {
        // Create AudioNavigatorFactory
        val navigatorFactory = AudioNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application)
        )

        audioNavigator = navigatorFactory!!.createNavigator(
            initialLocator,
            preferences
        ).getOrNull()!!

        editor = navigatorFactory.createAudioPreferencesEditor(preferences)

        audioNavigator!!.playback
            .throttleLatest(100.milliseconds)
            .onEach { onPlaybackChanged(it) }
            .launchIn(CoroutineScope(Dispatchers.Main))
            .let { jobs.add(it) }
    }

    override fun play() {
        play(null)
    }

    override fun play(fromLocator: Locator?) {
        if (fromLocator != null) {
            audioNavigator?.go(fromLocator)
        }

        audioNavigator?.play()
    }

    override fun pause() {
        audioNavigator?.pause()
    }

    override fun resume() {
        // TODO: Do we need to check if already playing?
        audioNavigator?.play()
    }

    fun onPlaybackChanged(pb: AudioNavigator.Playback) {
        Log.d(TAG, "::onPlaybackChanged $pb")

        // Create locator from Playback

        val an = audioNavigator
        if (an == null) {
            Log.e(TAG, ":onPlaybackChanged - missing audioNavigator")
            return
        }

        val position = pb.index
        val currentItem = an.readingOrder.items[position]
        val pubCurrentItem = publication.readingOrder[position]
        val chapterTitle = pubCurrentItem.title
        val chapterDuration = currentItem.duration
        val chapterOffset = pb.offset
        val chapterOffsetSeconds = chapterOffset.inWholeSeconds
        val chapterProgression =
            chapterOffset.inWholeMilliseconds / chapterDuration!!.inWholeMilliseconds

        // TODO: calculate totalProgression and add to Locations.
        val totalDuration = an.readingOrder.duration
        val currentTotalOffset = an.readingOrder.items.slice(0..position - 1)
            .sumOf { it.duration?.inWholeMilliseconds ?: 0 } + chapterOffset.inWholeMilliseconds
        val totalProgression = currentTotalOffset / (totalDuration?.inWholeMilliseconds ?: 1)

        val locations = Locator.Locations(
            arrayOf("t=${chapterOffsetSeconds}").toList(),
            progression = chapterProgression.toDouble(),
            position,
            totalProgression = totalProgression.toDouble()
        )

        var locator =
            Locator(currentItem.href, pubCurrentItem.mediaType ?: MP3, chapterTitle, locations)
        // Submit Locator to flutter channel
    }

    fun dispose() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        audioNavigator?.close()
        audioNavigator = null
        editor = null
    }
}