@file:OptIn(ExperimentalReadiumApi::class)

package dk.nota.flutter_readium

import android.graphics.Color
import android.util.Log
import org.json.JSONObject
import org.readium.navigator.media.tts.android.AndroidTtsEngine.Voice.Id
import org.readium.navigator.media.tts.android.AndroidTtsPreferences
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Language

private fun readiumColorFromCSS(cssColor: String): ReadiumColor {
    val color = Color.parseColor(cssColor)
    return ReadiumColor(color)
}

fun androidTtsPreferencesFromMap(ttsPrefsMap: Map<String, Any>): AndroidTtsPreferences {
    try {
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

fun decorationStyleFromMap(decoMap: Map<String, String>): Decoration.Style? {
    try {
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
            backgroundColor = prefMap["backgroundColor"]?.let { readiumColorFromCSS(it) }
                ?: defaults?.backgroundColor,
            textColor = prefMap["textColor"]?.let { readiumColorFromCSS(it) } ?: defaults?.textColor
        )
        return newPreferences
    } catch (ex: Exception) {
        Log.e("ReadiumExtensions", "Error mapping JSONObject to EpubPreferences: $ex")
        return null
    }
}
