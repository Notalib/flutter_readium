@file:OptIn(ExperimentalReadiumApi::class, ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.util.Log
import androidx.core.graphics.toColorInt
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.navigator.media.tts.android.AndroidTtsEngine.Voice.Id
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Language
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingResource
import org.readium.r2.shared.util.resource.filename
import org.readium.r2.navigator.preferences.Color as ReadiumColor

private const val TAG = "ReadiumExtensions"

private fun readiumColorFromCSS(cssColor: String): ReadiumColor {
    val color = cssColor.toColorInt()
    return ReadiumColor(color)
}

fun androidTtsPreferencesFromMap(ttsPrefsMap: Map<String, Any>?): AndroidTtsPreferences {
    try {
        if (ttsPrefsMap == null) {
            return AndroidTtsPreferences()
        }

        val speed = ttsPrefsMap["speed"] as Double?
        val pitch = ttsPrefsMap["pitch"] as Double?
        val voiceId = ttsPrefsMap["voiceIdentifier"] as String?
        val langOverrideStr = ttsPrefsMap["languageOverride"] as String?
        val langOverride = if (langOverrideStr != null) Language(langOverrideStr) else null
        val overrideMap = if (langOverride != null && voiceId != null)
            mapOf(langOverride to Id(voiceId)) else emptyMap()
        return AndroidTtsPreferences(langOverride, pitch, speed, overrideMap)
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping Map to AndroidTtsPreferences: $ex")
        return AndroidTtsPreferences()
    }
}

fun decorationFromMap(decoMap: Map<String, Any>): Decoration? {
    try {
        val id = decoMap["decorationId"] as String
        val locator = Locator.fromJSON(jsonDecode(decoMap["locator"] as String) as JSONObject)
            ?: throw Exception("Failed to deserialize locator")
        val style = decorationStyleFromMap(decoMap["style"] as Map<String, String>)
            ?: throw Exception("Failed to deserialize decoration")
        return Decoration(id, locator, style)
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

fun decorationStyleFromMap(decoMap: Map<String, String>?): Decoration.Style? {
    try {
        if (decoMap == null) return null

        val styleStr = decoMap["style"]
        val tintColorStr = decoMap["tint"]!!
        val style = when (styleStr) {
            "underline" -> Decoration.Style.Underline(readiumColorFromCSS(tintColorStr).int)
            "highlight" -> Decoration.Style.Highlight(readiumColorFromCSS(tintColorStr).int)
            else -> Decoration.Style.Highlight(readiumColorFromCSS(tintColorStr).int)
        }
        return style
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to Decoration.Style: $ex")
        return null
    }
}

fun epubPreferencesFromMap(
    prefMap: Map<String, String>,
    defaults: EpubPreferences?,
): EpubPreferences? {
    try {
      val newPreferences = EpubPreferences(
            fontFamily = prefMap["fontFamily"]?.let { FontFamily(it) } ?: defaults?.fontFamily,
            fontSize = prefMap["fontSize"]?.toDoubleOrNull() ?: defaults?.fontSize,
            fontWeight = prefMap["fontWeight"]?.toDoubleOrNull() ?: defaults?.fontWeight,
            scroll = prefMap["verticalScroll"]?.toBoolean() ?: defaults?.scroll,
            backgroundColor = prefMap["backgroundColor"]?.let { readiumColorFromCSS(it) } ?: defaults?.backgroundColor,
            textColor = prefMap["textColor"]?.let { readiumColorFromCSS(it) } ?: defaults?.textColor,
            pageMargins = prefMap["pageMargins"]?.toDoubleOrNull() ?: defaults?.pageMargins,
      )
      return newPreferences
    } catch (ex: Exception) {
      Log.e("ReadiumExtensions", "Error mapping JSONObject to EpubPreferences: $ex")
      return null
    }
}

fun exoPlayerPreferencesFromMap(
    prefMap: Map<String, String>,
    defaults: ExoPlayerPreferences?
): ExoPlayerPreferences? {
    try {
        return ExoPlayerPreferences(
            pitch = prefMap["pitch"]?.toDoubleOrNull() ?: defaults?.pitch,
            speed = prefMap["speed"]?.toDoubleOrNull() ?: defaults?.speed
        )
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to ExoPlayerPreferences: $ex")
    }
    return null
}

private const val READIUM_FLUTTER_PATH_PREFIX =
    "https://readium/assets/flutter_assets/packages/flutter_readium"

// Helper for injecting extra files into an epub
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
