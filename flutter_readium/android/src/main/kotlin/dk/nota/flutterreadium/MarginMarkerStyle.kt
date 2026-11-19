package dk.nota.flutterreadium

import android.os.Parcelable
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
        /** Icon names the template can render. Keep in sync with `MarginMarkerIcon` on the Dart side. */
        val KNOWN_ICONS = setOf("bookmark")
    }
}
