package dk.nota.flutter_readium

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi

private const val TAG = "FlutterPdfPreferences"

// PdfiumPreferences in kotlin-toolkit 3.1.2 has no paginated mode — Pdfium is
// always continuous-scroll. The Dart-side `PDFLayout.paginated` is therefore
// mapped to `scrollAxis = HORIZONTAL`, which gives the closest equivalent
// (single-page-wide viewport, one page per swipe). `scrollHorizontal` maps to
// the same axis. `scrollVertical` maps to `Axis.VERTICAL`.
@OptIn(ExperimentalReadiumApi::class)
data class FlutterPdfPreferences(
    val readingProgression: ReadingProgression? = null,
    val scrollAxis: Axis? = null,
) {
    fun toPdfiumPreferences(): PdfiumPreferences =
        PdfiumPreferences(
            readingProgression = readingProgression,
            scrollAxis = scrollAxis,
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
            val layoutStr = map["layout"] as? String
            val scrollAxis = layoutStr?.let {
                when (it) {
                    "paginated", "scrollHorizontal" -> Axis.HORIZONTAL
                    "scrollVertical" -> Axis.VERTICAL
                    else -> null
                }
            }
            return FlutterPdfPreferences(
                readingProgression = readingProgression,
                scrollAxis = scrollAxis,
            )
        }
    }
}
