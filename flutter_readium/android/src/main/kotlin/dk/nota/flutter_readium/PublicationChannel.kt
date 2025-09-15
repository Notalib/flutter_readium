@file:OptIn(ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.util.Log
import dk.nota.flutter_readium.navigators.Navigator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.getOrElse

private const val TAG = "PublicationChannel"

internal const val publicationChannelName = "dk.nota.flutter_readium/main"

internal class PublicationMethodCallHandler() :
    MethodChannel.MethodCallHandler, Navigator.TimeBaseListener {

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

                    val pubJsonManifest =
                        publication.manifest.toJSON().toString().replace("\\/", "/")

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

                    val pubJsonManifest =
                        publication.manifest.toJSON().toString().replace("\\/", "/")
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
                        ReadiumReader.ttsEnable(ttsPrefs)

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
                    try {
                        ReadiumReader.ttsSetPreferences(prefs)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ttsSetPreferences", "Failed to set preferences", e.message)
                    }
                }

                "ttsSetDecorationStyle" -> {
                    val args = call.arguments as List<*>
                    val uttDecoMap = args[0] as Map<String, String>?
                    val rangeDecoMap = args[1] as Map<String, String>?
                    val uttStyle = decorationStyleFromMap(uttDecoMap)
                    val rangeStyle = decorationStyleFromMap(rangeDecoMap)
                    try {
                        ReadiumReader.ttsSetDecorationStyle(uttStyle, rangeStyle)
                        result.success(null)
                    } catch (e: Error) {
                        result.error(
                            "ttsSetPreferences",
                            "Failed to set decoration style",
                            e.message
                        )
                    }
                }

                "ttsGetAvailableVoices" -> {
                    val androidVoices = ReadiumReader.ttsGetAvailableVoices()
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

                    ReadiumReader.ttsSetPreferredVoice(voiceId, language)

                    result.success(null)
                }

                "play" -> {
                    val args = call.arguments as List<*>
                    val fromLocatorStr = args[0] as String?
                    val fromLocator = fromLocatorStr?.let {
                        Locator.fromJSON(JSONObject(it))
                    }

                    ReadiumReader.play(fromLocator)

                    result.success(null)
                }

                "pause" -> {
                    ReadiumReader.pause()
                    result.success(null)
                }

                "resume" -> {
                    ReadiumReader.resume()

                    result.success(null)
                }

                "stop" -> {
                    ReadiumReader.stop()

                    result.success(null)
                }

                "next" -> {
                    ReadiumReader.next()

                    result.success(null)
                }

                "previous" -> {
                    ReadiumReader.previous()

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

                "audioEnable" -> {
                    val args = call.arguments as List<*>
                    // 0 is AudioPreferences
                    val prefsStr = args[0] as String?
                    val locatorStr = args[1] as String?
                    val publication = ReadiumReader.currentPublication
                    val preferences =
                        prefsStr?.let { FlutterAudioPreferences.fromJSON(JSONObject(it)) }
                    // TODO: Save preferences, on ReadiumReader?
                    val exoPreferences =
                        preferences?.toExoPlayerPreferences() ?: ExoPlayerPreferences()
                    val locator = locatorStr?.let { Locator.fromJSON(JSONObject(it)) }

                    if (publication == null) {
                        result.error("audioEnable", "Publication not found", null)
                        return@launch
                    }

                    ReadiumReader.audioEnable(locator, exoPreferences)

                    result.success(null)
                }

                "audioSetPreferences" -> {
                    val prefsStr = call.arguments as String?
                    val preferences =
                        prefsStr?.let { FlutterAudioPreferences.fromJSON(JSONObject(it)) }
                    // TODO: Save preferences, on ReadiumReader?
                    val exoPreferences =
                        preferences?.toExoPlayerPreferences() ?: ExoPlayerPreferences()
                    ReadiumReader.audioUpdatePreferences(exoPreferences)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onTimebasePlaybackStateChanged(playbackState: Navigator.PlaybackState) {
        Log.d(TAG, ":onTimebasePlaybackStateChanged $playbackState")
    }

    override fun onTimebaseCurrentLocatorChanges(locator: Locator) {
        Log.d(TAG, ":onTimebaseCurrentLocatorChanges $locator")
    }
}
