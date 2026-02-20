package dk.nota.flutter_readium

import android.graphics.Color
import android.os.Parcelable
import org.readium.r2.navigator.Decoration
import kotlinx.parcelize.Parcelize

// TODO: Decision on appropriate defaults
// TODO: Can this be made configurable at built time?
// TODO: More complex styles? Like bold or italic plus background and text colors?
private val defaultUtteranceStyle = Decoration.Style.Highlight(tint = Color.YELLOW)
private val defaultCurrentRangeStyle = Decoration.Style.Underline(tint = Color.RED)

/**
 * Decoration preferences used in the Flutter Readium plugin.
 */
@Parcelize
data class FlutterDecorationPreferences(
    /**
     * Style for utterance decoration.
     */
    var utteranceStyle: Decoration.Style? = defaultUtteranceStyle,

    /**
     * Style for current reading range decoration.
     */
    var currentRangeStyle: Decoration.Style? = defaultCurrentRangeStyle
) : Parcelable {
    companion object {
        /**
         * Create Decoration.Style from map.
         */
        fun fromMap(
            uttDecoMap: Map<*, *>?,
            rangeDecoMap: Map<*, *>?
        ): FlutterDecorationPreferences {
            return FlutterDecorationPreferences(
                decorationStyleFromMap(uttDecoMap) ?: defaultUtteranceStyle,
                decorationStyleFromMap(rangeDecoMap) ?: defaultCurrentRangeStyle,
            )
        }
    }
}
