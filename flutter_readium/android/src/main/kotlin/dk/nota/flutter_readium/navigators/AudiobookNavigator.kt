package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferencesEditor
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "AudioNavigator"

private const val currentTimebaseLocatorKey = "currentTimebaseLocator"

private const val audioPreferencesKey = "audioPreferencesKey"

@OptIn(ExperimentalReadiumApi::class)
class AudiobookNavigator(
    publication: Publication,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    private var initialPreferences: ExoPlayerPreferences = ExoPlayerPreferences()
) : TimebasedNavigator(publication, timebasedListener, initialLocator) {
    private var audioNavigator: AudioNavigator<*, *>? = null
    private var editor: ExoPlayerPreferencesEditor? = null

    val preferences: ExoPlayerPreferences?
        get() = editor?.preferences

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    override suspend fun initNavigator() {
        // Create AudioNavigatorFactory
        val navigatorFactory = AudioNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application)
        )

        if (navigatorFactory == null) {
            // TODO: Better Error handling, if the book isn't an audiobook the factory is null.
            Log.e(TAG, ":initNavigator - Couldn't create AudioNavigatorFactory")
            throw Exception("Couldn't create AudioNavigatorFactory")
        }

        audioNavigator = navigatorFactory.createNavigator(
            this@AudiobookNavigator.initialLocator,
            initialPreferences
        ).getOrElse { error ->
            Log.e(TAG, ":initNavigator - $error")
            throw Exception(PublicationError.invoke(error).message)
        }

        editor = navigatorFactory.createAudioPreferencesEditor(initialPreferences)

        setupNavigatorListeners()
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

    /// Updates Audio preferences, does not override current preferences if props are null
    fun updatePreferences(prefs: ExoPlayerPreferences) {
        editor?.apply {
            pitch.set(prefs.pitch)
            speed.set(prefs.speed)
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator
        if (navigator == null) {
            return
        }

        // Listen to state changes
        navigator.playback
            .throttleLatest(100.milliseconds)
            .distinctUntilChangedBy { it -> "${it.state}|${it.playWhenReady}" }
            .onEach { onPlaybackStateChanged(it) }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach {
                onCurrentLocatorChanges(it)
                state[currentTimebaseLocatorKey] = it
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebaseLocatorKey,
                (state[currentTimebaseLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            preferences?.let {
                putString(
                    audioPreferencesKey,
                    Json.encodeToString(ExoPlayerPreferences.serializer(), it)
                )
            }
        }
    }

    override fun dispose() {
        super.dispose()

        audioNavigator?.close()
        audioNavigator = null
        editor = null
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle
        ): AudiobookNavigator {
            val locator = state.getString(currentTimebaseLocatorKey)
                ?.let { Locator.fromJSON(JSONObject(it)) }
            val preferences = state.getString(audioPreferencesKey)
                ?.let { Json.decodeFromString<ExoPlayerPreferences>(it) } ?: ExoPlayerPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}