package dk.nota.flutterreadium

import androidx.annotation.ColorInt
import kotlinx.parcelize.Parcelize
import org.readium.r2.navigator.Decoration

/**
 * Margin marker: a text [label] or built-in [icon] floated into the page margin, level with the
 * first line of the range. [side] is "start" or "end" (logical, so it flips in RTL).
 * A transparent [tint] means no tint was set.
 */
@Parcelize
data class MarginMarkerStyle(
    val label: String?,
    val icon: String?,
    val side: String,
    @ColorInt override val tint: Int,
) : Decoration.Style,
    Decoration.Style.Tinted {
    companion object {
        /** SVG path data (24x24 viewBox) by `MarginMarkerIcon` name. Keep in sync with Dart, iOS and web. */
        val ICON_PATHS =
            mapOf(
                "bookmark" to "M6 2h12a1 1 0 0 1 1 1v19l-7-4-7 4V3a1 1 0 0 1 1-1z",
                "note" to "M4 3h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9l-5 4v-4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM7 7v2h10V7zm0 4v2h7v-2z",
                "star" to "M12 2l2.9 6.9 7.1.6-5.4 4.7 1.6 7-6.2-3.8-6.2 3.8 1.6-7L2 9.5l7.1-.6z",
            )
    }
}
