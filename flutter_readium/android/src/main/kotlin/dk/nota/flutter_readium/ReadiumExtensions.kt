@file:OptIn(InternalReadiumApi::class)

package dk.nota.flutter_readium

import android.graphics.Color
import android.util.Log
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Locator

private fun readiumColorFromCSS(cssColor: String): ReadiumColor {
  val color = Color.parseColor(cssColor)
  return ReadiumColor(color)
}

fun decorationFromMap(decoMap: Map<String, String>): Decoration? {
  try {
    val id = decoMap["decorationId"] as String
    val locator = Locator.fromJSON(jsonDecode(decoMap["locator"]))
    val style = decorationStyleFromMap(decoMap["style"])
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
      backgroundColor = prefMap["backgroundColor"]?.let { readiumColorFromCSS(it) } ?: defaults?.backgroundColor,
      textColor = prefMap["textColor"]?.let { readiumColorFromCSS(it) } ?: defaults?.textColor
    )
    return newPreferences
  } catch (ex: Exception) {
    Log.e("ReadiumExtensions", "Error mapping JSONObject to EpubPreferences: $ex")
    return null
  }
}
