package dk.nota.flutterreadium

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi

private const val TAG = "FlutterPdfPreferences"

// PdfiumPreferences in kotlin-toolkit 3.1.2 has no `scroll` field — the Pdfium
// engine is continuous-scroll only, so the Dart-side `scroll` preference is
// accepted but has no effect on Android. iOS PDFKit supports it.
@OptIn(ExperimentalReadiumApi::class)
data class FlutterPdfPreferences(
    val readingProgression: ReadingProgression? = null,
) {
    fun toPdfiumPreferences(): PdfiumPreferences =
        PdfiumPreferences(
            readingProgression = readingProgression,
        )

    companion object {
        fun fromMap(map: Map<String, Any>): FlutterPdfPreferences {
            val rpStr = map["readingProgression"] as? String
            val readingProgression = rpStr?.let {
                when (it) {
                    "ltr" -> ReadingProgression.LTR
                    "rtl" -> ReadingProgression.RTL
                    else -> null
                }
            }
            return FlutterPdfPreferences(readingProgression = readingProgression)
        }
    }
}
