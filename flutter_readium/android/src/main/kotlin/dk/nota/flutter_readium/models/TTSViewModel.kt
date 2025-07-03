package dk.nota.flutter_readium.models

import android.app.Application
import android.content.Context
import android.graphics.Color
import android.util.Log
import dk.nota.flutter_readium.currentReadiumReaderView
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.readium.navigator.media.common.MediaNavigator
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
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.tokenizer.DefaultTextContentTokenizer
import org.readium.r2.shared.util.tokenizer.TextUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "TTSViewModel"
private const val TTS_DECORATION_ID_UTTERANCE = "tts-utterance"
private const val TTS_DECORATION_ID_CURRENT_RANGE = "tts-range"

@OptIn(ExperimentalReadiumApi::class)
internal class TTSViewModel(
  private val appContext: Context,
  private val publication: Publication,
  private var preferences: AndroidTtsPreferences = AndroidTtsPreferences()
) {
  private val jobs = mutableListOf<Job>()

  // TODO: Decision on appropriate defaults
  private var utteranceStyle: Decoration.Style? = Decoration.Style.Highlight(tint = Color.YELLOW)
  private var currentRangeStyle: Decoration.Style? = Decoration.Style.Underline(tint = Color.RED)

  private var ttsNavigator: TtsNavigator<AndroidTtsSettings, AndroidTtsPreferences, AndroidTtsEngine.Error, AndroidTtsEngine.Voice>? = null

  suspend fun initNavigator() {
    val factory = TtsNavigatorFactory(
      this.appContext as Application,
      this.publication,
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
      val firstVisibleLocator = currentReadiumReaderView?.getFirstVisibleLocator()

      val ttsNavigator = factory.createNavigator(listener, firstVisibleLocator, preferences).getOrElse {
        Log.e(TAG, "ttsEnable: failed to create navigator: $it")
        throw Exception("ttsEnable: failed to create navigator: $it")
      }

      // Setup streaming listeners for locator & decoration updates.
      setupNavigatorListeners(ttsNavigator)

      this@TTSViewModel.ttsNavigator = ttsNavigator
    }.await()
  }

  fun setUtteranceStyle(style: Decoration.Style?) {
    this.utteranceStyle = style
  }

  fun setCurrentRangeStyle(style: Decoration.Style?) {
    this.currentRangeStyle = style
  }

  fun play(fromLocator: Locator?) {
    if (fromLocator != null) {
        ttsNavigator?.go(fromLocator)
    }
    ttsNavigator?.play()
  }

  fun pause() = ttsNavigator?.pause()
  fun resume() = ttsNavigator?.play()
  fun nextUtterance() = ttsNavigator?.skipToNextUtterance()
  fun previousUtterance() = ttsNavigator?.skipToPreviousUtterance()

  /// Updates TTS preferences, does not override current preferences if props are null
  fun updatePreferences(prefs: AndroidTtsPreferences) {
    this.preferences = this.preferences.plus(prefs)
    this.ttsNavigator?.submitPreferences(this.preferences)
  }

  fun setPreferredVoice(voiceId: String, lang: String?) {
    // Modify existing map of voice overrides, in case user sets multiple preferred voices.
    val voices = this.preferences.voices?.toMutableMap() ?: mutableMapOf()
    // If no lang provided, assume client wants to override currently spoken language.
    val language = if (lang != null) Language(lang) else this.ttsNavigator?.settings?.value?.language
    if (language != null) {
      voices[language] = AndroidTtsEngine.Voice.Id(voiceId)
      this.updatePreferences(AndroidTtsPreferences(voices = voices))
    }
  }

  val voices: Set<AndroidTtsEngine.Voice>
    get() = ttsNavigator?.voices ?: emptySet()

  private fun setupNavigatorListeners(navigator: TtsNavigator<*, *, *, *>) {
    // Listen to state changes
    navigator.playback
      .throttleLatest(100.milliseconds)
      .map { it.state }
      .distinctUntilChanged()
      .onEach { state ->
        Log.d(TAG, "ttsPlayback: state=$state")
        if (state is MediaNavigator.State.Failure) {
          CoroutineScope(Dispatchers.Main).launch {
            //TODO: Send to Flutter plugin state stream.
          }
        }
      }
      .launchIn(CoroutineScope(Dispatchers.Main))
      .let { jobs.add(it) }

    // Listen to utterance updates and apply decorations
    navigator.location
      .map { Pair(it.utteranceLocator, it.tokenLocator) }
      .distinctUntilChanged()
      .onEach { (uttLocator, tokenLocator) ->
        val decorations = mutableListOf<Decoration>()
        this.utteranceStyle?.let {
          decorations.add(Decoration(
            id = TTS_DECORATION_ID_UTTERANCE,
            locator = uttLocator,
            style = it,
          ))
        }
        letIfBothNotNull(tokenLocator, this.currentRangeStyle)?.let { (locator, style) ->
          decorations.add(
            Decoration(
              id = TTS_DECORATION_ID_CURRENT_RANGE,
              locator = locator,
              style = style,
            )
          )
        }
        CoroutineScope(Dispatchers.Main).launch {
          currentReadiumReaderView?.applyDecorations(decorations, group = "tts")
        }
      }
      .launchIn(CoroutineScope(Dispatchers.IO))
      .let { jobs.add(it) }

    // Listen to location changes and turn pages (throttled).
    navigator.location
      .throttleLatest(0.4.seconds)
      .map { it.tokenLocator ?: it.utteranceLocator }
      .distinctUntilChanged()
      .onEach { locator ->
        currentReadiumReaderView?.justGoToLocator(locator, animated = true)
      }
      .launchIn(CoroutineScope(Dispatchers.Main))
      .let { jobs.add(it) }
  }

  fun dispose() {
    jobs.forEach { it.cancel() }
    jobs.clear()
    ttsNavigator?.close()
    ttsNavigator = null
  }
}
