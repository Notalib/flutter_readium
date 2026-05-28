package dk.nota.flutter_readium

import android.os.Parcelable
import androidx.annotation.ColorInt
import kotlinx.parcelize.Parcelize
import org.readium.r2.navigator.Decoration

/** Spotlight: tinted box behind the active range + surrounding text dims via box-shadow. */
@Parcelize
data class SpotlightStyle(
    @ColorInt override val tint: Int,
) : Decoration.Style,
    Decoration.Style.Tinted

/** Ruler: full-viewport-width tinted stripe across each decorated text line. */
@Parcelize
data class RulerStyle(
    @ColorInt override val tint: Int,
) : Decoration.Style,
    Decoration.Style.Tinted
