package dk.nota.flutter_readium

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi

private const val TAG = "FlutterPdfPreferences"

@OptIn(ExperimentalReadiumApi::class)
data class FlutterPdfPreferences(
    val scroll: Boolean? = null,
    val readingProgression: ReadingProgression? = null,
) {
    fun toPdfiumPreferences(): PdfiumPreferences =
        PdfiumPreferences(
            scroll = scroll,
            readingProgression = readingProgression,
        )

    companion object {
        fun fromMap(map: Map<String, Any>): FlutterPdfPreferences {
            val scroll = map["scroll"] as? Boolean
            val rpStr = map["readingProgression"] as? String
            val readingProgression = rpStr?.let {
                when (it) {
                    "ltr" -> ReadingProgression.LTR
                    "rtl" -> ReadingProgression.RTL
                    else -> null
                }
            }
            return FlutterPdfPreferences(scroll = scroll, readingProgression = readingProgression)
        }
    }
}
