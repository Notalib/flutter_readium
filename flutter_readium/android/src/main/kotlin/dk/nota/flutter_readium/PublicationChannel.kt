@file:OptIn(ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.getOrElse

private const val TAG = "PublicationChannel"

internal const val publicationChannelName = "dk.nota.flutter_readium/main"

@ExperimentalCoroutinesApi
internal class PublicationMethodCallHandler() :
    MethodChannel.MethodCallHandler {

    @OptIn(InternalReadiumApi::class, ExperimentalReadiumApi::class)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val res = handleMethodCallsQueue(
                    call.method,
                    call.arguments
                ).getOrElse { error ->
                    result.publicationError(call.method, error)
                    return@launch
                }

                if (res is Unit) {
                    result.success(null)
                    return@launch
                }

                result.success(res)
            } catch (e: NotImplementedError) {
                result.notImplemented()
            } catch (e: Exception) {
                Log.e(TAG, "Exception: $e")
                Log.e(TAG, "${e.stackTrace}")

                // TODO: Handle unknown errors better.
                result.error(
                    e.javaClass.toString(),
                    e.toString(),
                    e.stackTraceToString()
                )
            }
        }
    }

    /**
     * This function can be used to handle method calls sequentially if needed.
     */
    private suspend fun handleMethodCallsQueue(
        method: String,
        arguments: Any?
    ): Try<Any?, PublicationError> {
        when (method) {
            "setCustomHeaders" -> {
                @Suppress("UNCHECKED_CAST")
                val args = arguments as? Map<String, Map<String, String>> ?: emptyMap()
                val httpHeaders = args["httpHeaders"] ?: emptyMap()

                ReadiumReader.setDefaultHttpHeaders(httpHeaders)
                return Try.success(null)
            }

            "loadPublication" -> {
                val args = arguments as List<Any?>
                val pubUrlStr = args[0] as String
                return loadPublication(pubUrlStr)
            }

            "openPublication" -> {
                val args = arguments as List<Any?>
                val pubUrlStr = args[0] as String

                return openPublication(pubUrlStr)
            }

            "closePublication" -> {
                Log.d(TAG, "Close publication")

                ReadiumReader.closePublication()
                return Try.success(null)
            }

            "ttsEnable" -> {
                val args = arguments as Map<*, *>?
                val ttsPrefs = FlutterTtsPreferences.fromMap(args)
                return ttsEnable(ttsPrefs)
            }

            "ttsSetPreferences" -> {
                val args = arguments as Map<*, *>?
                val ttsPrefs = FlutterTtsPreferences.fromMap(args)

                return ttsSetPreferences(ttsPrefs)
            }

            "ttsSetDecorationStyle" -> {
                val args = arguments as List<*>
                val uttDecoMap = args[0] as Map<*, *>?
                val rangeDecoMap = args[1] as Map<*, *>?
                val uttStyle = decorationStyleFromMap(uttDecoMap)
                val rangeStyle = decorationStyleFromMap(rangeDecoMap)

                return ttsSetDecorationStyle(uttStyle, rangeStyle)
            }

            "ttsGetAvailableVoices" -> {
                ttsGetAvailableVoices().let { voices ->
                    return Try.success(voices)
                }
            }

            "ttsSetVoice" -> {
                val args = arguments as List<*>
                val voiceId = args[0] as String?
                val language = args[1] as String?

                ReadiumReader.ttsSetPreferredVoice(voiceId, language)

                return Try.success(null)
            }

            "play" -> {
                val args = arguments as List<*>
                val fromLocator = (args[0] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                ReadiumReader.play(fromLocator)

                return Try.success(null)
            }

            "pause" -> {
                ReadiumReader.pause()

                return Try.success(null)
            }

            "resume" -> {
                ReadiumReader.resume()

                return Try.success(null)
            }

            "stop" -> {
                ReadiumReader.stop()

                return Try.success(null)
            }

            "next" -> {
                ReadiumReader.next()

                return Try.success(null)
            }

            "previous" -> {
                ReadiumReader.previous()

                return Try.success(null)
            }

            "goToLocator" -> {
                val args = arguments as List<*>
                val locator = (args[0] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                if (locator == null) {
                    throw Exception("goToLocator: failed to go to locator. Missing locator: ${args[0]} ")
                }

                ReadiumReader.goToLocator(locator)

                return Try.success(null)
            }

            "getLinkContent" -> {
                val args = arguments as List<Any?>
                val linkStr = args[0] as String
                val asString = args[1] as? Boolean ?: true
                val link = Link.fromJSON(JSONObject(linkStr))

                if (link == null) {
                    throw Exception("getLinkContent: failed to get resource. Missing link: $link")
                }

                return getLinkContent(link, asString)
            }

            "audioEnable" -> {
                val args = arguments as List<*>
                // 0 is AudioPreferences
                val prefs = args[0] as Map<*, *>?

                val preferences = prefs?.let { FlutterAudioPreferences.fromMap(it) }
                    ?: FlutterAudioPreferences()

                val locator = (args[1] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                return audioEnable(locator, preferences)
            }

            "audioSetPreferences" -> {
                val prefsStr = arguments as String?
                val preferences =
                    prefsStr?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                        ?: FlutterAudioPreferences()

                ReadiumReader.audioUpdatePreferences(preferences)

                return Try.success(null)
            }

            else -> {
                throw NotImplementedError()
            }
        }
    }

    /**
     * Load and return the publication manifest from a URL without opening it.
     */
    private suspend fun loadPublication(pubUrlStr: String): Try<String, PublicationError> {
        val publication =
            ReadiumReader.loadPublicationFromUrl(pubUrlStr).getOrElse { error ->
                return Try.failure(error)
            }

        val pubJsonManifest =
            publication.manifest.toJSON().toString().replace("\\/", "/")

        // Close the publication to avoid leaks.
        publication.close()
        return Try.success(pubJsonManifest)
    }

    /**
     * Open a publication from a URL. If another publication is already opened, it will be closed first.
     *
     * There can be only one... opened publication at a time.
     */
    private suspend fun openPublication(pubUrlStr: String): Try<String, PublicationError> {
        val publication =
            ReadiumReader.openPublicationFromUrl(pubUrlStr).getOrElse { error ->
                return Try.failure(error)
            }

        val pubJsonManifest =
            publication.manifest.toJSON().toString().replace("\\/", "/")

        return Try.success(pubJsonManifest)
    }

    /**
     * Enable TTS reading with the provided preferences.
     */
    private suspend fun ttsEnable(prefs: FlutterTtsPreferences): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.ttsEnable(prefs)
        return Try.success(null)
    }

    /**
     * Update the TTS preferences. The TTS must be enabled first.
     */
    private suspend fun ttsSetPreferences(ttsPrefs: FlutterTtsPreferences): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.ttsSetPreferences(ttsPrefs)
        return Try.success(null)
    }

    /**
     * Set the TTS decoration styles for the utterance and the range.
     * If null is provided the default style will be used.
     */
    suspend fun ttsSetDecorationStyle(
        uttStyle: Decoration.Style?,
        rangeStyle: Decoration.Style?
    ): Try<Any?, PublicationError> {
        try {
            ReadiumReader.ttsSetDecorationStyle(uttStyle, rangeStyle)
            return Try.success(null)
        } catch (e: Error) {
            return Try.failure(PublicationError.Unknown("Failed to set decoration style"))
        }
    }

    /**
     * Get the list of available TTS voices on the device.
     */
    fun ttsGetAvailableVoices(): List<String> {
        val androidVoices = ReadiumReader.ttsGetAvailableVoices()
        if (androidVoices == null) {
            return listOf()
        }

        val voicesJson = androidVoices.map {
            JSONObject().apply {
                put("identifier", it.id.value)
                put(
                    "name",
                    it.id.value
                ) // ID should be mapped to a readable name on Flutter side.
                put("quality", it.quality.name.lowercase())
                put("requiresNetwork", it.requiresNetwork)
                put("language", it.language.code)
            }.toString()
        }

        return voicesJson
    }

    /**
     * Get the content of a publication resource via a Link.
     * If asString is true the content is returned as a String, otherwise as ByteArray
     */
    private suspend fun getLinkContent(link: Link, asString: Boolean): Try<Any, PublicationError> {
        val publication = ReadiumReader.currentPublication
            ?: return Try.failure(
                PublicationError.Unavailable()
            )

        Log.d(TAG, "Use publication = $publication")

        val resource = publication.get(link) ?: run {
            throw Exception("getLinkContent: failed to find pub resource via link: pubId=${publication.metadata.identifier},link=$link")
        }
        val resourceBytes = resource.read().getOrElse {
            throw Exception("getLinkContent: failed to read resource. ${it.message}")
        }

        return Try.success(if (asString) String(resourceBytes) else resourceBytes)
    }

    /**
     * Enable audio (audiobook) reading with optional locator to start from and audio preferences.
     */
    private suspend fun audioEnable(
        locator: Locator?,
        preferences: FlutterAudioPreferences
    ): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.audioEnable(locator, preferences)
        return Try.success(null)
    }
}

/**
 * Send a PublicationError back to Flutter via MethodChannel.Result
 */
fun MethodChannel.Result.publicationError(method: String, error: PublicationError) {
    Log.e(
        TAG,
        "$method: PublicationError<${error.errorCode}>: ${error.message}, cause=${error.cause}"
    )

    this.error(
        error.errorCode.name,
        error.message,
        error.cause
    )
}
