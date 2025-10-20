package dk.nota.flutter_readium

import android.graphics.Color
import org.readium.r2.navigator.Decoration
import java.io.Serializable

// TODO: Decision on appropriate defaults
// TODO: Can this be made configurable at built time?
// TODO: More complex styles? Like bold or italic plus background and text colors?
private val defaultUtteranceStyle = Decoration.Style.Highlight(tint = Color.YELLOW)
private val defaultCurrentRangeStyle = Decoration.Style.Underline(tint = Color.RED)

data class FlutterDecorationPreferences(
    var utteranceStyle: Decoration.Style? = defaultUtteranceStyle,
    var currentRangeStyle: Decoration.Style? = defaultCurrentRangeStyle
) : Serializable {
    companion object {
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
