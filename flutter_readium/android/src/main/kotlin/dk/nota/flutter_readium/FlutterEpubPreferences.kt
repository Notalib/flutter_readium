package dk.nota.flutter_readium

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.ColumnCount
import org.readium.r2.navigator.preferences.Configurable
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.ImageFilter
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.navigator.preferences.Spread
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.navigator.preferences.Theme
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.util.Language

private const val TAG = "FlutterEpubPreferences"

private const val topMarginCssVariable = "--FLUTTER_READIUM-first-element-top-margin"
private const val blackAndWhiteComicModeCssVariable = "--FLUTTER_READIUM-black-white-comic-mode"

@OptIn(ExperimentalReadiumApi::class)
@Serializable
data class FlutterEpubPreferences(
    val backgroundColor: String? = null,
    val columnCount: ColumnCount? = null,
    val fontFamily: FontFamily? = null,
    val fontSize: Double? = null,
    val fontWeight: Double? = null,
    val hyphens: Boolean? = null,
    val imageFilter: ImageFilter? = null,
    val language: Language? = null,
    val letterSpacing: Double? = null,
    val ligatures: Boolean? = null,
    val lineHeight: Double? = null,
    val pageMargins: Double? = null,
    val paragraphIndent: Double? = null,
    val paragraphSpacing: Double? = null,
    val publisherStyles: Boolean? = null,
    val readingProgression: ReadingProgression? = null,
    val scroll: Boolean? = null,
    val spread: Spread? = null,
    val textAlign: TextAlign? = null,
    val textColor: String? = null,
    val textNormalization: Boolean? = null,
    val theme: Theme? = null,
    val typeScale: Double? = null,
    val verticalText: Boolean? = null,
    val wordSpacing: Double? = null,
    val blackAndWhiteComicMode: Boolean? = false,
    val disableSynchronization: Boolean? = false,
    val firstElementTopMargin: Int? = null,
) : Configurable.Preferences<FlutterEpubPreferences> {
    override fun plus(other: FlutterEpubPreferences): FlutterEpubPreferences =
        FlutterEpubPreferences(
            backgroundColor = other.backgroundColor ?: backgroundColor,
            columnCount = other.columnCount ?: columnCount,
            fontFamily = other.fontFamily ?: fontFamily,
            fontWeight = other.fontWeight ?: fontWeight,
            fontSize = other.fontSize ?: fontSize,
            hyphens = other.hyphens ?: hyphens,
            imageFilter = other.imageFilter ?: imageFilter,
            language = other.language ?: language,
            letterSpacing = other.letterSpacing ?: letterSpacing,
            ligatures = other.ligatures ?: ligatures,
            lineHeight = other.lineHeight ?: lineHeight,
            pageMargins = other.pageMargins ?: pageMargins,
            paragraphIndent = other.paragraphIndent ?: paragraphIndent,
            paragraphSpacing = other.paragraphSpacing ?: paragraphSpacing,
            publisherStyles = other.publisherStyles ?: publisherStyles,
            readingProgression = other.readingProgression ?: readingProgression,
            scroll = other.scroll ?: scroll,
            spread = other.spread ?: spread,
            textAlign = other.textAlign ?: textAlign,
            textColor = other.textColor ?: textColor,
            textNormalization = other.textNormalization ?: textNormalization,
            theme = other.theme ?: theme,
            typeScale = other.typeScale ?: typeScale,
            verticalText = other.verticalText ?: verticalText,
            wordSpacing = other.wordSpacing ?: wordSpacing,
            blackAndWhiteComicMode = other.blackAndWhiteComicMode ?: blackAndWhiteComicMode,
            disableSynchronization = other.disableSynchronization ?: disableSynchronization,
            firstElementTopMargin = other.firstElementTopMargin ?: firstElementTopMargin,
        )

    fun toEpubPreferences(): EpubPreferences =
        EpubPreferences(
            backgroundColor = backgroundColor?.let { readiumColorFromCSS(it) },
            columnCount,
            fontFamily,
            fontSize,
            fontWeight,
            hyphens,
            imageFilter,
            language,
            letterSpacing,
            ligatures,
            lineHeight,
            pageMargins,
            paragraphIndent,
            paragraphSpacing,
            publisherStyles,
            readingProgression,
            scroll = scroll,
            spread,
            textAlign,
            textColor = textColor?.let { readiumColorFromCSS(it) },
            textNormalization,
            theme,
            typeScale,
            verticalText,
            wordSpacing,
        )

    fun toCustomCssVariables(): Map<String, String?> {
        val map = mutableMapOf<String, String?>()
        map[topMarginCssVariable] = firstElementTopMargin?.let { "${it}px" }
        map[blackAndWhiteComicModeCssVariable] = if (blackAndWhiteComicMode == true) "1" else null
        return map
    }

    fun toInjectableStyleSheet(): String =
        """<style id="flutter_readium_style">:root {${
            toCustomCssVariables().filter { it.value != null }
                .map { (key, value) -> "$key: $value !important" }
                .joinToString(separator = ";")
        }}</style>""".trimIndent()

    companion object {
        fun fromMap(map: Map<String, Any>): FlutterEpubPreferences {
            val element = mapToJsonObject(map)
            return Json.decodeFromJsonElement(serializer(), element)
        }

        fun fromJson(jsonString: String): FlutterEpubPreferences = Json.decodeFromString<FlutterEpubPreferences>(jsonString)
    }
}
