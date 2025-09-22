package dk.nota.flutter_readium.navigators

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.readium.navigator.media.tts.TtsNavigator
import org.readium.navigator.media.tts.TtsNavigator.Listener
import org.readium.navigator.media.tts.TtsNavigatorFactory
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.navigator.media.tts.android.AndroidTtsPreferencesEditor
import org.readium.navigator.media.tts.android.AndroidTtsSettings
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer
import org.readium.r2.shared.util.tokenizer.TextUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "TTSViewModel"
private const val TTS_DECORATION_ID_UTTERANCE = "tts-utterance"
private const val TTS_DECORATION_ID_CURRENT_RANGE = "tts-range"

private const val currentTimebasedLocatorKey = "currentTimebasedLocator"

private const val ttsPreferencesKey = "ttsPreferences"

// TODO: Send audio-locator event to dart on locator change.
// TODO: Extend locator with chapter info
// TODO: Common interface for audio and TTS navigator.

@OptIn(ExperimentalReadiumApi::class)
class TTSNavigator(
    publication: Publication,
    timeBaseListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: AndroidTtsPreferences = AndroidTtsPreferences()
) : TimebasedNavigator(publication, timeBaseListener, initialLocator) {
    // TODO: Decision on appropriate defaults
    private var utteranceStyle: Decoration.Style? = Decoration.Style.Highlight(tint = Color.YELLOW)
    private var currentRangeStyle: Decoration.Style? = Decoration.Style.Underline(tint = Color.RED)

    private var ttsNavigator: TtsNavigator<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>? =
        null

    private var editor: AndroidTtsPreferencesEditor? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    override suspend fun initNavigator() {
        val navigatorFactory = TtsNavigatorFactory(
            ReadiumReader.application,
            publication,
            tokenizerFactory = { language ->
                DefaultTextContentTokenizer(unit = TextUnit.Sentence, language = language)
            }
        ) ?: throw Exception("This publication cannot be played with the TTS navigator")

        val listener = object : Listener {
            override fun onStopRequested() {
                Log.d(TAG, "TtsListener::onStopRequested")
            }
        }
        CoroutineScope(Dispatchers.Main).async {
            val firstVisibleLocator = ReadiumReader.currentReaderWidget?.getFirstVisibleLocator()

            ttsNavigator =
                navigatorFactory.createNavigator(listener, firstVisibleLocator, preferences)
                    .getOrElse {
                        Log.e(TAG, "ttsEnable: failed to create navigator: $it")
                        throw Exception("ttsEnable: failed to create navigator: $it")
                    }

            editor = navigatorFactory.createPreferencesEditor(preferences)

            // Setup streaming listeners for locator & decoration updates.
            setupNavigatorListeners()
        }.await()
    }

    fun setUtteranceStyle(style: Decoration.Style?) {
        utteranceStyle = style
    }

    fun setCurrentRangeStyle(style: Decoration.Style?) {
        currentRangeStyle = style
    }

    override fun play() {
        play(null)
    }

    override fun play(fromLocator: Locator?) {
        if (fromLocator != null) {
            ttsNavigator?.go(fromLocator)
        }

        ttsNavigator?.play()
    }

    override fun pause() {
        ttsNavigator?.pause()
    }

    override fun resume() {
        ttsNavigator?.play()
    }

    fun nextUtterance() = ttsNavigator?.skipToNextUtterance()

    fun previousUtterance() = ttsNavigator?.skipToPreviousUtterance()

    /// Updates TTS preferences, does not override current preferences if props are null
    fun updatePreferences(prefs: AndroidTtsPreferences) {
        editor?.apply {
            voices.set(prefs.voices)
            language.set(prefs.language)
            pitch.set(prefs.pitch)
            speed.set(prefs.speed)
        }
    }

    fun setPreferredVoice(voiceId: String, lang: String?) {
        // Modify existing map of voice overrides, in case user sets multiple preferred voices.
        val voices = preferences.voices?.toMutableMap() ?: mutableMapOf()
        // If no lang provided, assume client wants to override currently spoken language.
        val language =
            if (lang != null) Language(lang) else ttsNavigator?.settings?.value?.language
        if (language != null) {
            voices[language] = AndroidTtsEngine.Voice.Id(voiceId)
            updatePreferences(AndroidTtsPreferences(voices = voices))
        }
    }

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
            .distinctUntilChangedBy { it -> "${it.state}|${it.playWhenReady}" }
            .distinctUntilChanged()
            .onEach { onPlaybackStateChanged(it) }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Listen to utterance updates and apply decorations
        navigator.location
            .map { Pair(it.utteranceLocator, it.tokenLocator) }
            .distinctUntilChanged()
            .onEach { (uttLocator, tokenLocator) ->
                val decorations = mutableListOf<Decoration>()
                utteranceStyle?.let {
                    decorations.add(
                        Decoration(
                            id = TTS_DECORATION_ID_UTTERANCE,
                            locator = uttLocator,
                            style = it,
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
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Listen to location changes and turn pages (throttled).
        navigator.location
            .throttleLatest(0.4.seconds)
            .map { it.tokenLocator ?: it.utteranceLocator }
            .distinctUntilChanged()
            .onEach { locator ->
                // TODO: This should be handled by an event
                ReadiumReader.currentReaderWidget?.justGoToLocator(locator, animated = true)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach {
                onCurrentLocatorChanges(it)
                state[currentTimebasedLocatorKey] = it
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebasedLocatorKey,
                (state[currentTimebasedLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            editor?.preferences?.let {
                putString(
                    ttsPreferencesKey,
                    Json.encodeToString(AndroidTtsPreferences.serializer(), it)
                )
            }
        }
    }

    override fun dispose() {
        super.dispose()

        ttsNavigator?.close()
        ttsNavigator = null
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
                ?.let { Json.decodeFromString<AndroidTtsPreferences>(it) }
                ?: AndroidTtsPreferences()

            return TTSNavigator(publication, listener, locator, preferences)
        }
    }
}

