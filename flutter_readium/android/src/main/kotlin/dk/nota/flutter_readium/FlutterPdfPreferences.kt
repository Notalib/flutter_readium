package dk.nota.flutter_readium

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Fit
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi

// PdfiumPreferences in kotlin-toolkit has no paginated mode — Pdfium is
// always continuous-scroll. The Dart-side `PDFLayout.paginated` is therefore
// mapped to `scrollAxis = HORIZONTAL`, which gives the closest equivalent
// (single-page-wide viewport, one page per swipe). `scrollHorizontal` maps to
// the same axis. `scrollVertical` maps to `Axis.VERTICAL`.
//
// Dart-side `PDFFit.page` maps to Pdfium `Fit.CONTAIN`. `PDFFit.auto` has no
// Pdfium equivalent and is ignored on Android.
@OptIn(ExperimentalReadiumApi::class)
data class FlutterPdfPreferences(
    val readingProgression: ReadingProgression? = null,
    val scrollAxis: Axis? = null,
    val fit: Fit? = null,
    val pageSpacing: Double? = null,
) {
    fun toPdfiumPreferences(): PdfiumPreferences =
        PdfiumPreferences(
            fit = fit,
            pageSpacing = pageSpacing,
            readingProgression = readingProgression,
            scrollAxis = scrollAxis,
        )

    companion object {
        fun fromMap(map: Map<String, Any>): FlutterPdfPreferences {
            val rpStr = map["readingProgression"] as? String
            val readingProgression =
                rpStr?.let {
                    when (it) {
                        "ltr" -> ReadingProgression.LTR
                        "rtl" -> ReadingProgression.RTL
                        else -> null
                    }
                }
            val layoutStr = map["layout"] as? String
            val scrollAxis =
                layoutStr?.let {
                    when (it) {
                        "paginated", "scrollHorizontal" -> Axis.HORIZONTAL
                        "scrollVertical" -> Axis.VERTICAL
                        else -> null
                    }
                }
            val fitStr = map["fit"] as? String
            val fit =
                fitStr?.let {
                    when (it) {
                        "page", "contain" -> Fit.CONTAIN

                        "width" -> Fit.WIDTH

                        // Kotlin toolkit Pdfium supports only CONTAIN and WIDTH.
                        "auto" -> null

                        else -> null
                    }
                }
            val pageSpacing = (map["pageSpacing"] as? Number)?.toDouble()
            return FlutterPdfPreferences(
                readingProgression = readingProgression,
                scrollAxis = scrollAxis,
                fit = fit,
                pageSpacing = pageSpacing,
            )
        }
    }
}
