@file:OptIn(InternalReadiumApi::class)

package dk.nota.flutter_readium

import android.graphics.Color
import android.util.Log
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.InternalReadiumApi

private fun readiumColorFromCSS(cssColor: String): ReadiumColor {
  val color = Color.parseColor(cssColor)
  return ReadiumColor(color)
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
