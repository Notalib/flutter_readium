package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.ControlPanelInfoType
import dk.nota.flutter_readium.FlutterAudioPreferences
import dk.nota.flutter_readium.PluginMediaServiceFacade
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
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

const val currentTimebaseLocatorKey = "currentTimebaseLocator"

const val audioPreferencesKey = "audioPreferencesKey"

/**
 * Navigator for pure Audiobook publications using Readium's AudioNavigator.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
open class AudiobookNavigator(
    publication: Publication,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: FlutterAudioPreferences
) : TimebasedNavigator<AudioNavigator.Playback>(publication, timebasedListener, initialLocator) {
    /**
     * The AudioNavigator provided by Readium..
     */
    protected var audioNavigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>? = null

    /**
     * The MediaServiceFacade to manage MediaSession interactions, notifications, etc.
     */
    protected var mediaServiceFacade: PluginMediaServiceFacade? = null

    override suspend fun initNavigator() {
        // Create AudioNavigatorFactory
        val navigatorFactory = ExoPlayerNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application, metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
                    publication = publication,
                    trackCount = pub.readingOrder.size,
                    controlPanelInfoType = preferences.controlPanelInfoType ?: ControlPanelInfoType.STANDARD
                )})
        )

        if (navigatorFactory == null) {
            // TODO: Better Error handling, if the book isn't an audiobook the factory is null.
            Log.e(TAG, ":initNavigator - Couldn't create AudioNavigatorFactory")
            throw Exception("Couldn't create AudioNavigatorFactory")
        }

        mainScope.async {
            audioNavigator = navigatorFactory.createNavigator(
                this@AudiobookNavigator.initialLocator,
                preferences.toExoPlayerPreferences()
            ).getOrElse { error ->
                Log.e(TAG, ":initNavigator - $error")
                throw Exception(PublicationError.invoke(error).message)
            }

            mediaServiceFacade = PluginMediaServiceFacade(ReadiumReader.application).apply {
                session
                    .flatMapLatest { it?.navigator?.playback ?: MutableStateFlow(null) }
                    .onEach { playback ->
                        when (val state = (playback?.state as? AudioNavigator.State)) {
                            null, AudioNavigator.State.Ready, AudioNavigator.State.Buffering -> {
                                // Do nothing
                            }

                            is AudioNavigator.State.Ended -> {
                                mediaServiceFacade?.closeSession()
                            }

                            is AudioNavigator.State.Failure<*> -> {
                                Log.e(TAG, "AudioNavigator failure: ${state.error}")
                                //onPlaybackError(state.error)
                            }
                        }
                    }.launchIn(mainScope)
            }

            setupNavigatorListeners()
        }.await()
    }

    override suspend fun play(fromLocator: Locator?) {
        mainScope.async {
            if (fromLocator != null) {
                audioNavigator?.go(fromLocator)
            }

            try {
                Log.d(TAG, "Opening MediaSession")
                mediaServiceFacade?.openSession(audioNavigator!!)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening MediaSession: ${e.message}")
                audioNavigator?.close()
                return@async
            }

            audioNavigator?.play()
        }.await()
    }

    override suspend fun pause() {
        mainScope.async {
            audioNavigator?.pause()
        }.await()
    }

    override suspend fun resume() {
        mainScope.async {
            // TODO: Do we need to check if already playing?
            audioNavigator?.play()
        }.await()
    }

    override suspend fun goBack() {
        mainScope.async {
            audioNavigator?.skip((-preferences.seekInterval).seconds)
        }.await()
    }

    override suspend fun goForward() {
        mainScope.async {
            audioNavigator?.skip((preferences.seekInterval).seconds)
        }.await()
    }

    override suspend fun goToLocator(locator: Locator) {
        val navigator = audioNavigator ?: return
        mainScope.async {
            navigator.go(locator)
        }
    }

    override suspend fun seekTo(offset: Double) {
        mainScope.async {
            audioNavigator?.skip(offset.seconds)
        }.await()
    }

    /**
     * Updates Audio preferences, does not override current preferences if props are null
     */
    fun updatePreferences(prefs: FlutterAudioPreferences) {
        preferences = preferences + prefs

        mainScope.async {
            audioNavigator?.submitPreferences(preferences.toExoPlayerPreferences())
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator
        if (navigator == null) {
            Log.e(TAG, ": setupNavigatorListeners - navigator is null")
            return
        }

        // Listen to state changes
        navigator.playback
            .throttleLatest(100.milliseconds)
            .distinctUntilChangedBy { pb ->
                "${pb.state}|${pb.playWhenReady}"
            }
            .onEach { pb ->
                onPlaybackStateChanged(pb)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle buffered changes
        navigator.playback
            .throttleLatest(250.milliseconds)
            .distinctUntilChangedBy { pb -> pb.buffered }
            .onEach { pb ->
                timebaseListener.onTimebasedBufferChanged(pb.buffered)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle current locator changes
        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                state[currentTimebaseLocatorKey] = locator
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        mainScope.async {
            navigator.settings
                .collect { s ->
                    Log.d(TAG, ": AudioNavigator settings changed: $s")
                }
        }
    }

    override fun onPlaybackStateChanged(pb: AudioNavigator.Playback) {
        when (pb.state) {
            is AudioNavigator.State.Failure<*> -> {
                val audioState = pb.state as AudioNavigator.State.Failure<*>
                val error = audioState.error

                Log.e(
                    TAG,
                    ": onPlaybackStateChanged - audio error: Message=${error.message} cause=${error.cause}"
                )

                timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Failure)
                timebaseListener.onTimebasedPlaybackFailure(
                    PublicationError.invoke(error)
                )
            }

            else -> {
                super.onPlaybackStateChanged(pb)
            }
        }
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

        mainScope.launch {
            mediaServiceFacade?.closeSession()

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

