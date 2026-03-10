package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.ControlPanelInfoType
import dk.nota.flutter_readium.FlutterTtsPreferences
import dk.nota.flutter_readium.PluginMediaServiceFacade
import dk.nota.flutter_readium.PublicationError
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.debounce
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

private const val TAG = "TTSNavigator"

private const val TTS_DECORATION_ID_UTTERANCE = "tts-utterance"

private const val TTS_DECORATION_ID_CURRENT_RANGE = "tts-range"

private const val currentTimebasedLocatorKey = "currentTimebasedLocator"

private const val ttsPreferencesKey = "ttsPreferences"

// TODO: Extend locator with chapter info

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class TTSNavigator(
    publication: Publication,
    timebaseListener: TimebasedListener,
    initialLocator: Locator?,
    var preferences: FlutterTtsPreferences = FlutterTtsPreferences()
) : TimebasedNavigator<TtsNavigator.Playback>(publication, timebaseListener, initialLocator) {
    val decorationGroup = "tts"

    private var ttsNavigator: TtsNavigator<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>? =
        null

    private var mediaServiceFacade: PluginMediaServiceFacade? = null

    override suspend fun initNavigator() {
        val navigatorFactory = TtsNavigatorFactory(
            ReadiumReader.application,
            publication,
            tokenizerFactory = { language ->
                DefaultTextContentTokenizer(unit = TextUnit.Sentence, language = language)
            },
            metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
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
        withScope(mainScope) {
            ttsNavigator =
                navigatorFactory.createNavigator(
                    listener,
                    initialLocator,
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
        }
    }

    override suspend fun play() {
        play(null)
    }

    override suspend fun play(fromLocator: Locator?) {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, ":play called when ttsNavigator was null")
            return
        }

        val mediaFacade = mediaServiceFacade ?: run {
            Log.e(TAG, ":play called when mediaServiceFacade was null")
            return
        }

        withScope(mainScope) {
            fromLocator?.let {
                navigator.go(it)
            }

            try {
                Log.d(TAG, "::play - Opening MediaSession")
                if (mediaFacade.session.value == null) {
                    mediaFacade.openSession(navigator)
                }
            } catch (e: Exception) {
                Log.e(TAG, "::play - Failed to open MediaSession: $e")
                navigator.close()
                return@withScope
            }

            navigator.play()
        }
    }

    override suspend fun pause() {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, "Cannot pause TTS playback: navigator is null")
            return
        }

        withScope(mainScope) {
            try {
                navigator.pause()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause TTS playback: $e")
            }
        }
    }

    override suspend fun resume() {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, "Cannot resume TTS playback: navigator is null")
            return
        }

        withScope(mainScope) {
            try {
                navigator.play()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resume TTS playback: $e")
            }
        }
    }

    /**
     * Skip to previous utterance (sentence).
     */
    override suspend fun goBack() {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, "::goBack ttsNavigator is null")
            return
        }

        withScope(mainScope) {
            if (navigator.hasPreviousUtterance()) {
                navigator.skipToPreviousUtterance()
            }
        }
    }

    /**
     * Skip to next utterance (sentence).
     */
    override suspend fun goForward() {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, "::goBack goForward is null")
            return
        }

        withScope(mainScope) {
            if (navigator.hasNextUtterance()) {
                navigator.skipToNextUtterance()
            }
        }
    }

    override suspend fun goToLocator(locator: Locator) {
        val navigator = ttsNavigator ?: run {
            Log.e(TAG, "::goToLocator called when ttsNavigator was null")
            return
        }
        withScope(mainScope) {
            decorateCurrentUtterance(locator, null)
            onCurrentLocatorChanges(locator)
            navigator.go(locator)
        }
    }

    override suspend fun seekTo(offset: Double) {
        Log.w(TAG, ":seekTo is not implemented for TTS playback")
    }

    /**
     * Called when decorations (e.g., highlights) need to be updated.
     */
    suspend fun decorationsUpdated() {
        val navigator = ttsNavigator ?: run {
            Log.d(TAG, ":decorationsUpdated: navigator is null")
            return
        }

        val location = navigator.location.value
        decorateCurrentUtterance(location.utteranceLocator, location.tokenLocator)
    }


    /// Updates TTS preferences, does not override current preferences if props are null
    suspend fun updatePreferences(prefs: FlutterTtsPreferences) {
        withScope(mainScope) {
            preferences = preferences.plus(prefs)

            val androidPrefs = preferences.toAndroidTtsPreferences()
            ttsNavigator?.submitPreferences(androidPrefs)
        }
    }

    /**
     * Set preferred voice for a given language. If lang is null, override voice for currently spoken language.
     */
    suspend fun setPreferredVoice(voiceId: String, lang: String) {
        // Modify existing map of voice overrides, in case user sets multiple preferred voices.
        val voices = preferences.voices?.toMutableMap() ?: mutableMapOf()

        voices[lang] = voiceId
        updatePreferences(FlutterTtsPreferences(voices = voices))
    }

    /*
     * Get available voices from TTS engine
     */
    val voices: Set<AndroidTtsEngine.Voice>
        get() = ttsNavigator?.voices ?: emptySet()

    @OptIn(FlowPreview::class)
    override fun setupNavigatorListeners() {
        val navigator = ttsNavigator ?: return

        // Listen to state changes
        navigator.playback
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
            .debounce(0.4.seconds)
            .map { it.tokenLocator ?: it.utteranceLocator }
            .distinctUntilChanged()
            .onEach { locator ->
                ReadiumReader.onTimebasedLocationChanged(locator)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        navigator.currentLocator
            .debounce(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                val emittingLocator =
                    ReadiumReader.epubEnrichLocatorWithTocHref(locator)
                onCurrentLocatorChanges(emittingLocator)
                state[currentTimebasedLocatorKey] = emittingLocator
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }
    }

    /**
     * Apply decorations for the current utterance and token (word).
     */
    private suspend fun decorateCurrentUtterance(uttLocator: Locator, tokenLocator: Locator?) {
        val decorations = mutableListOf<Decoration>()
        val utteranceStyle = ReadiumReader.decorationStyle.utteranceStyle
        val currentRangeStyle = ReadiumReader.decorationStyle.currentRangeStyle
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

        ReadiumReader.applyDecorations(decorations, group = decorationGroup)
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebasedLocatorKey,
                (state[currentTimebasedLocatorKey] as? Locator)?.toJSON()?.toString()
            )

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

            ReadiumReader.applyDecorations(emptyList(), decorationGroup)

            ttsNavigator?.close()
            ttsNavigator = null
        }
    }

    override fun onPlaybackStateChanged(pb: TtsNavigator.Playback) {
        when (pb.state) {
            // Handle TTS-specific failure state
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

            return TTSNavigator(publication, listener, locator, preferences)
        }
    }
}
