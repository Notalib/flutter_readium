package dk.nota.flutter_readium.navigators

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.ControlPanelInfoType
import dk.nota.flutter_readium.FlutterTtsPreferences
import dk.nota.flutter_readium.PluginMediaServiceFacade
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import org.json.JSONObject
import org.readium.navigator.media.tts.TtsNavigator
import org.readium.navigator.media.tts.TtsNavigator.Listener
import org.readium.navigator.media.tts.TtsNavigatorFactory
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer
import org.readium.r2.shared.util.tokenizer.TextUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "TTSViewModel"
private const val TTS_DECORATION_ID_UTTERANCE = "tts-utterance"
private const val TTS_DECORATION_ID_CURRENT_RANGE = "tts-range"

private const val currentTimebasedLocatorKey = "currentTimebasedLocator"

private const val utteranceStyleKey = "utteranceStyle"

private const val currentRangeStyleKey = "currentRangeStyle"

private const val ttsPreferencesKey = "ttsPreferences"

// TODO: Extend locator with chapter info

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class TTSNavigator(
    publication: Publication,
    timebaseListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: FlutterTtsPreferences = FlutterTtsPreferences()
) : TimebasedNavigator<TtsNavigator.Playback>(publication, timebaseListener, initialLocator) {
    // TODO: Decision on appropriate defaults
    private var utteranceStyle: Decoration.Style? = Decoration.Style.Highlight(tint = Color.YELLOW)
    private var currentRangeStyle: Decoration.Style? = Decoration.Style.Underline(tint = Color.RED)

    private var ttsNavigator: TtsNavigator<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>? =
        null

    private var mediaServiceFacade: PluginMediaServiceFacade? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    override suspend fun initNavigator() {
        val navigatorFactory = TtsNavigatorFactory(
            ReadiumReader.application,
            publication,
            tokenizerFactory = { language ->
                DefaultTextContentTokenizer(unit = TextUnit.Sentence, language = language)
            },
            metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
                    context = ReadiumReader.application,
                    publication = publication,
                    trackCount = pub.readingOrder.size,
                    controlPanelInfoType = preferences.controlPanelInfoType
                        ?: ControlPanelInfoType.STANDARD
                )
            }
        ) ?: throw Exception("This publication cannot be played with the TTS navigator")

        val listener = object : Listener {
            override fun onStopRequested() {
                Log.d(TAG, "TtsListener::onStopRequested")
                mediaServiceFacade?.closeSession()
            }
        }

        val initialAndroidPreferences = preferences.toAndroidTtsPreferences()
        mainScope.async {
            val firstVisibleLocator = ReadiumReader.currentReaderWidget?.getFirstVisibleLocator()

            ttsNavigator =
                navigatorFactory.createNavigator(
                    listener,
                    firstVisibleLocator,
                    initialAndroidPreferences
                )
                    .getOrElse {
                        Log.e(TAG, "ttsEnable: failed to create navigator: $it")
                        throw Exception("ttsEnable: failed to create navigator: $it")
                    }

            // Setup streaming listeners for locator & decoration updates.
            setupNavigatorListeners()

            mediaServiceFacade = PluginMediaServiceFacade(ReadiumReader.application)
                .apply {
                    session
                        .flatMapLatest { it?.navigator?.playback ?: MutableStateFlow(null) }
                        .onEach { playback ->
                            when (val state = (playback?.state as? TtsNavigator.State)) {
                                null, TtsNavigator.State.Ready -> {
                                    // Do nothing
                                }

                                is TtsNavigator.State.Ended -> {
                                    mediaServiceFacade?.closeSession()
                                }

                                is TtsNavigator.State.Failure -> {
                                    Log.e(TAG, "TTSNavigator failure: ${state.error}")
                                    //onPlaybackError(state.error)
                                }
                            }
                        }.launchIn(mainScope)
                }
        }.await()
    }

    suspend fun setDecorationStyle(uttStyle: Decoration.Style?, rangeStyle: Decoration.Style?) {
        utteranceStyle = uttStyle
        currentRangeStyle = rangeStyle

        val navigator = ttsNavigator
        if (navigator == null) {
            Log.d(TAG, ":setDecorationStyle: navigator is null")
            return
        }

        val location = navigator.location.value
        mainScope.async {
            decorateCurrentUtterance(location.utteranceLocator, location.tokenLocator)
        }.await()
    }

    override suspend fun play() {
        play(null)
    }

    override suspend fun play(fromLocator: Locator?) {
        mainScope.async {
            if (fromLocator != null) {
                ttsNavigator?.go(fromLocator)
            }

            // TODO: Handle multiple calls to this function
            try {
                Log.d(TAG, "Opening MediaSession")
                mediaServiceFacade?.openSession(ttsNavigator!!)
                ttsNavigator?.play()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open MediaSession: $e")
                ttsNavigator?.close()
                return@async
            }
        }.await()
    }

    override suspend fun pause() {
        if (ttsNavigator == null) {
            Log.e(TAG, "Cannot pause TTS playback: navigator is null")
            return
        }

        mainScope.async {
            try {
                ttsNavigator?.pause()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause TTS playback: $e")
            }
        }.await()
    }

    override suspend fun resume() {
        if (ttsNavigator == null) {
            Log.e(TAG, "Cannot resume TTS playback: navigator is null")
            return
        }

        mainScope.async {
            try {
                ttsNavigator?.play()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resume TTS playback: $e")
            }
        }.await()
    }

    /**
     * Skip to previous utterance (sentence).
     */
    override suspend fun goBack() {
        val navigator = ttsNavigator ?: return
        mainScope.async {
            if (navigator.hasPreviousUtterance()) {
                navigator.skipToPreviousUtterance()
            }
        }.await()
    }

    /**
     * Skip to next utterance (sentence).
     */
    override suspend fun goForward() {
        val navigator = ttsNavigator ?: return
        mainScope.async {
            if (navigator.hasNextUtterance()) {
                navigator.skipToNextUtterance()
            }
        }.await()
    }

    override suspend fun goToLocator(locator: Locator) {
        val navigator = ttsNavigator ?: return
        mainScope.async {
            navigator.go(locator)
        }
    }


    /// Updates TTS preferences, does not override current preferences if props are null
    suspend fun updatePreferences(prefs: FlutterTtsPreferences) {
        mainScope.async {
            preferences = preferences.plus(prefs)

            ttsNavigator?.submitPreferences(preferences.toAndroidTtsPreferences())
        }.await()
    }

    /**
     * Set preferred voice for a given language. If lang is null, override voice for currently spoken language.
     */
    suspend fun setPreferredVoice(voiceId: String, lang: String?) {
        // Modify existing map of voice overrides, in case user sets multiple preferred voices.
        val voices = preferences.voices?.toMutableMap() ?: mutableMapOf()

        if (lang == null) return

        voices[lang] = voiceId
        updatePreferences(FlutterTtsPreferences(voices = voices))
    }

    /*
     * Get available voices from TTS engine
     */
    val voices: Set<AndroidTtsEngine.Voice>
        get() = ttsNavigator?.voices ?: emptySet()

    override fun setupNavigatorListeners() {
        val navigator = ttsNavigator
        if (navigator == null) {
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
                timebaseListener.onTimebasedBufferChanged(null)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Listen to utterance updates and apply decorations
        navigator.location
            .map { Pair(it.utteranceLocator, it.tokenLocator) }
            .distinctUntilChanged()
            .onEach { (uttLocator, tokenLocator) ->
                decorateCurrentUtterance(uttLocator, tokenLocator)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Listen to location changes and turn pages (throttled).
        navigator.location
            .throttleLatest(0.4.seconds)
            .map { it.tokenLocator ?: it.utteranceLocator }
            .distinctUntilChanged()
            .onEach { locator ->
                ReadiumReader.onTimebasedLocationChanged(locator)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                state[currentTimebasedLocatorKey] = locator
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }
    }

    private suspend fun decorateCurrentUtterance(uttLocator: Locator, tokenLocator: Locator?) {
        val decorations = mutableListOf<Decoration>()
        utteranceStyle?.let { style ->
            decorations.add(
                Decoration(
                    id = TTS_DECORATION_ID_UTTERANCE,
                    locator = uttLocator,
                    style = style,
                )
            )
        }
        letIfBothNotNull(tokenLocator, currentRangeStyle)?.let { (locator, style) ->
            decorations.add(
                Decoration(
                    id = TTS_DECORATION_ID_CURRENT_RANGE,
                    locator = locator,
                    style = style,
                )
            )
        }

        ReadiumReader.applyDecorations(decorations, group = "tts")
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebasedLocatorKey,
                (state[currentTimebasedLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            utteranceStyle?.let { utteranceStyle ->
                putParcelable(utteranceStyleKey, utteranceStyle)
            }

            currentRangeStyle?.let { currentRangeStyle ->
                putParcelable(currentRangeStyleKey, currentRangeStyle)
            }

            putString(
                ttsPreferencesKey,
                FlutterTtsPreferences.toJSON(preferences).toString()
            )
        }
    }

    override fun dispose() {
        super.dispose()

        mainScope.async {
            mediaServiceFacade?.closeSession()

            ttsNavigator?.close()
            ttsNavigator = null
        }
    }

    override fun onPlaybackStateChanged(pb: TtsNavigator.Playback) {
        when (pb.state) {
            is TtsNavigator.State.Failure -> {
                val ttsState = pb.state as TtsNavigator.State.Failure
                val error = ttsState.error

                // TODO: Handle TTS-specific errors?
                Log.e(
                    TAG,
                    ": onPlaybackStateChanged - TTS error: Message=${error.message} cause=${error.cause}"
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

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle
        ): TTSNavigator {
            val locator = state.getString(currentTimebasedLocatorKey)
                ?.let { Locator.fromJSON(JSONObject(it)) }
            val preferences = state.getString(ttsPreferencesKey)
                ?.let { FlutterTtsPreferences.fromJSON(it) }
                ?: FlutterTtsPreferences()

            val uttStyle = state.getParcelable<Decoration.Style>(utteranceStyleKey)
            val rangeStyle = state.getParcelable<Decoration.Style>(currentRangeStyleKey)

            return TTSNavigator(publication, listener, locator, preferences).apply {
                utteranceStyle = uttStyle
                currentRangeStyle = rangeStyle
            }
        }
    }
}
