@file:OptIn(ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.util.Log
import dk.nota.flutter_readium.navigators.AudioNavigator
import dk.nota.flutter_readium.navigators.TTSNavigator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.resource.filename
import org.readium.r2.streamer.PublicationOpener.OpenError

private const val TAG = "PublicationChannel"

internal const val publicationChannelName = "dk.nota.flutter_readium/main"
internal var currentReadiumReaderView: ReadiumReaderView? = null

/// Values must match order of OpeningReadiumExceptionType in readium_exceptions.dart.
internal fun openingExceptionIndex(exception: OpenError): Int =
    when (exception) {
        is OpenError.Reading -> 0
        is OpenError.FormatNotSupported -> 1
    }

private fun parseMediaType(mediaType: Any?): MediaType? {
    @Suppress("UNCHECKED_CAST")
    val list = mediaType as List<String?>? ?: return null
    return MediaType(list[0]!!)
}

internal class PublicationMethodCallHandler() :
    MethodChannel.MethodCallHandler {

    private var ttsNavigator: TTSNavigator? = null

    private var audioNavigator: AudioNavigator? = null

    @OptIn(InternalReadiumApi::class, ExperimentalReadiumApi::class)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.Main).launch {
            when (call.method) {
                "loadPublication" -> {
                    val args = call.arguments as List<Any?>
                    val pubUrlStr = args[0] as String

                    val publication = ReadiumReader.loadPublicationFromUrl(pubUrlStr).getOrElse {
                        Log.e(
                            TAG,
                            "loadPublication: Failed to load publication from URL. pubUrlStr=$pubUrlStr"
                        )
                        // TODO: errorCode doesn't look right
                        return@launch result.error("openPublication", it.message, it.cause)
                    }

                    val pubJsonManifest = publication.manifest.toJSON().toString().replace("\\/", "/")

                    // Close the publication to avoid leaks.
                    publication.close()
                    result.success(pubJsonManifest)
                }
                "openPublication" -> {
                    val args = call.arguments as List<Any?>
                    val pubUrlStr = args[0] as String

                    val publication = ReadiumReader.openPublicationFromUrl(pubUrlStr).getOrElse {
                        Log.e(
                            TAG,
                            "openPublication: Failed to load publication from URL. pubUrlStr=$pubUrlStr"
                        )
                        return@launch result.error("openPublication", it.message, it.cause)
                    }

                    // TODO: Initialize other necessary resources to prepare for reading this publication.

                    val pubJsonManifest = publication.manifest.toJSON().toString().replace("\\/", "/")
                    result.success(pubJsonManifest)
                }

                "closePublication" -> {
                    Log.d(TAG, "Close publication")
                    ReadiumReader.closePublication()
                }

                "ttsEnable" -> {
                    val args = call.arguments as Map<String, Any>?
                    val ttsPrefs = androidTtsPreferencesFromMap(args)

                    val publication = ReadiumReader.currentPublication
                    val pubUrl = ReadiumReader.currentPublicationUrl
                    if (publication == null) {
                        Log.e(
                            TAG,
                            "ttsEnable: Cannot enable TTS for un-opened publication. pubUrl=$pubUrl"
                        )
                        return@launch
                    }

                    try {
                        ttsNavigator = TTSNavigator(publication, ttsPrefs)
                        ttsNavigator!!.initNavigator()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(
                            TAG,
                            "ttsEnable: Failed to create TTSViewModel (likely navigator). pubUrl=$pubUrl"
                        )
                        result.error("ttsEnable", "Failed to create TTSModel", e.message)
                    }
                }

                "ttsSetPreferences" -> {
                    val args = call.arguments as Map<String, Any>
                    val prefs = androidTtsPreferencesFromMap(args)
                    ttsNavigator?.updatePreferences(prefs)
                }

                "ttsSetDecorationStyle" -> {
                    val args = call.arguments as List<*>
                    val uttDecoMap = args[0] as Map<String, String>?
                    val rangeDecoMap = args[1] as Map<String, String>?
                    val uttStyle = decorationStyleFromMap(uttDecoMap)
                    val rangeStyle = decorationStyleFromMap(rangeDecoMap)
                    ttsNavigator?.setUtteranceStyle(uttStyle)
                    ttsNavigator?.setCurrentRangeStyle(rangeStyle)
                }

                "ttsStart" -> {
                    val args = call.arguments as List<*>
                    val fromLocatorStr = args[0] as String?
                    val fromLocator = if (fromLocatorStr != null) {
                        Locator.fromJSON(JSONObject(fromLocatorStr))
                    } else {
                        currentReadiumReaderView?.getFirstVisibleLocator()
                    }
                    ttsNavigator?.play(fromLocator)
                    result.success(null)
                }

                "ttsPause" -> {
                    ttsNavigator?.pause()
                    result.success(null)
                }

                "ttsResume" -> {
                    ttsNavigator?.resume()
                    result.success(null)
                }

                "ttsStop" -> {
                    ttsNavigator?.dispose()
                    // Remove any current TTS decorations
                    currentReadiumReaderView?.applyDecorations(emptyList(), "tts")
                    result.success(null)
                }

                "ttsNext" -> {
                    ttsNavigator?.nextUtterance()
                    result.success(null)
                }

                "ttsPrevious" -> {
                    ttsNavigator?.previousUtterance()
                    result.success(null)
                }

                "ttsGetAvailableVoices" -> {
                    val androidVoices = ttsNavigator?.voices
                    val voicesJson = androidVoices?.map {
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
                    result.success(voicesJson)
                }

                "ttsSetVoice" -> {
                    val args = call.arguments as List<*>
                    val voiceId = args[0] as String?
                    val language = args[1] as String?
                    if (voiceId != null) {
                        ttsNavigator?.setPreferredVoice(voiceId, language)
                    }
                    result.success(null)
                }

                "getLinkContent" -> {
                    try {
                        val args = call.arguments as List<Any?>
                        val linkStr = args[0] as String
                        val asString = args[1] as? Boolean ?: true
                        val link = Link.fromJSON(JSONObject(linkStr))
                        val publication = ReadiumReader.currentPublication

                        if (publication == null || link == null) {
                            throw Exception("getLinkContent: failed to get resource. Missing pub or link: $publication, $link")
                        }

                        Log.d(TAG, "Use publication = $publication")

                        val resource = publication.get(link) ?: run {
                            throw Exception("getLinkContent: failed to find pub resource via link: pubId=${publication.metadata.identifier},link=$link")
                        }
                        val resourceBytes = resource.read().getOrElse {
                            throw Exception("getLinkContent: failed to read resource. ${it.message}")
                        }

                        CoroutineScope(Dispatchers.Main).launch {
                            if (asString) {
                                result.success(String(resourceBytes))
                            } else {
                                result.success(resourceBytes)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception: $e")
                        Log.e(TAG, "${e.stackTrace}")
                        CoroutineScope(Dispatchers.Main).launch {
                            result.error(
                                e.javaClass.toString(),
                                e.toString(),
                                e.stackTraceToString()
                            )
                        }
                    }
                }

                "audioStart" -> {
                    val args = call.arguments as List<*>
                    val speed = args[0] as Double? ?: 1.0
                    val locatorStr = args[1] as String?
                    val publication = ReadiumReader.currentPublication
                    val locator = locatorStr?.let { Locator.fromJSON(JSONObject(it)) }

                    if (publication == null) {
                        result.error("audioStart", "Publication not found", null)
                        return@launch
                    }

                    audioNavigator = AudioNavigator(publication, locator, ExoPlayerPreferences())
                    audioNavigator?.initNavigator()
                    audioNavigator?.play()
                    // TODO: Create AudioReaderFragment here, or within the ReadiumReaderView?
                    //
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

private const val READIUM_FLUTTER_PATH_PREFIX =
    "https://readium/assets/flutter_assets/packages/flutter_readium"

fun Resource.injectScriptsAndStyles(): Resource =
    TransformingResource(this) { bytes ->
        val props = this.properties().getOrNull()
        val filename = props?.filename

        // Skip all non-html files
        if (filename?.endsWith("html", ignoreCase = true) != true) {
            return@TransformingResource Try.success(bytes)
        }

        val content = bytes.toString(Charsets.UTF_8).trim()
        val headEndIndex = content.indexOf("</head>", 0, true)
        if (headEndIndex == -1) {
            Log.w(TAG, "No </head> element found, cannot inject scripts in: $filename")
            return@TransformingResource Try.success(bytes)
        }

        if (content.substring(0, headEndIndex).contains(READIUM_FLUTTER_PATH_PREFIX)) {
            Log.d(TAG, "Skip injecting - already done for: $filename")
            return@TransformingResource Try.success(bytes)
        }

        Log.d(TAG, "Injecting files into: $filename")

        val injectLines = listOf(
            """<script type="text/javascript" src="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/comics.js"></script>""",
            """<script type="text/javascript" src="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/epub.js"></script>""",
            """<script type="text/javascript">const isAndroid = true; const isIos = false;</script>""",
            """<link rel="stylesheet" type="text/css" href="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/comics.css"></link>""",
            """<link rel="stylesheet" type="text/css" href="$READIUM_FLUTTER_PATH_PREFIX/assets/helpers/epub.css"></link>""",
        )
        val newContent = StringBuilder(content)
            .insert(headEndIndex, "\n" + injectLines.joinToString("\n") + "\n")
            .toString()

        Try.success(newContent.toByteArray())
    }
