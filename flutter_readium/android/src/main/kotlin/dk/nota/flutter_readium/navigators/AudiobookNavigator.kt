package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerNavigatorFactory
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "AudioNavigator"

private const val currentTimebaseLocatorKey = "currentTimebaseLocator"

private const val audioPreferencesKey = "audioPreferencesKey"

@OptIn(ExperimentalReadiumApi::class)
class AudiobookNavigator(
    publication: Publication,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: FlutterAudioPreferences
) : TimebasedNavigator(publication, timebasedListener, initialLocator) {
    private var audioNavigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    override suspend fun initNavigator() {
        // Create AudioNavigatorFactory
        val navigatorFactory = ExoPlayerNavigatorFactory(
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
            preferences.toExoPlayerPreferences()
        ).getOrElse { error ->
            Log.e(TAG, ":initNavigator - $error")
            throw Exception(PublicationError.invoke(error).message)
        }

        setupNavigatorListeners()
    }

    override fun play(fromLocator: Locator?) {
        mainScope.async {
            if (fromLocator != null) {
                audioNavigator?.go(fromLocator)
            }

            audioNavigator?.play()
        }
    }

    override fun pause() {
        mainScope.async {
            audioNavigator?.pause()
        }
    }

    override fun resume() {
        mainScope.async {
            // TODO: Do we need to check if already playing?
            audioNavigator?.play()
        }
    }

    fun goBack() {
        mainScope.async {
            audioNavigator?.skip((-preferences.seekInterval).seconds)
        }
    }

    fun goForward() {
        mainScope.async {
            audioNavigator?.skip((preferences.seekInterval).seconds)
        }
    }

    /// Updates Audio preferences, does not override current preferences if props are null
    fun updatePreferences(prefs: FlutterAudioPreferences) {
        preferences = preferences + prefs

        mainScope.async {
            audioNavigator?.submitPreferences(preferences.toExoPlayerPreferences())
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

            putString(
                audioPreferencesKey,
                FlutterAudioPreferences.toJSON(preferences).toString()
            )
        }
    }

    override fun dispose() {
        super.dispose()

        mainScope.async {
            audioNavigator?.close()
            audioNavigator = null
        }
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle
        ): AudiobookNavigator {
            val locator = state.getString(currentTimebaseLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(audioPreferencesKey)
                ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                ?: FlutterAudioPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}