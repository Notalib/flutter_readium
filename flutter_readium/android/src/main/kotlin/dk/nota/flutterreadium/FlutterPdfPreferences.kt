package dk.nota.flutterreadium

import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.preferences.Axis
import org.readium.r2.navigator.preferences.Fit
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.shared.ExperimentalReadiumApi

// Dart-side `PDFLayout.paginated` maps to `scroll = false` (always horizontal). `scrollAxis` only
// applies in scroll mode, so the scroll layouts set `scroll = true` together with the axis.
//
// Dart-side `PDFFit.page` maps to Pdfium `Fit.CONTAIN`. `PDFFit.auto` has no
// Pdfium equivalent and is ignored on Android.
@OptIn(ExperimentalReadiumApi::class)
data class FlutterPdfPreferences(
    val readingProgression: ReadingProgression? = null,
    val scroll: Boolean? = null,
    val scrollAxis: Axis? = null,
    val fit: Fit? = null,
    val pageSpacing: Double? = null,
) {
    fun toPdfiumPreferences(): PdfiumPreferences =
        PdfiumPreferences(
            fit = fit,
            pageSpacing = pageSpacing,
            readingProgression = readingProgression,
            scroll = scroll,
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
            val (scroll, scrollAxis) =
                when (layoutStr) {
                    "paginated" -> false to null
                    "scrollHorizontal" -> true to Axis.HORIZONTAL
                    "scrollVertical" -> true to Axis.VERTICAL
                    else -> null to null
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
                scroll = scroll,
                scrollAxis = scrollAxis,
                fit = fit,
                pageSpacing = pageSpacing,
            )
        }
    }
}
