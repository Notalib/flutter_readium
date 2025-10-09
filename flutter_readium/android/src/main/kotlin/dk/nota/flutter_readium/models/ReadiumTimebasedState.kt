package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.navigators.TimebasedNavigator
import org.json.JSONObject
import org.readium.r2.shared.JSONable
import org.readium.r2.shared.publication.Locator

/**
 * State of a timebased navigator to be sent to the Flutter side
 */
data class ReadiumTimebasedState(
    /**
     * Current timebased locator
     */
    val locator: Locator?,

    /**
     *  Current state of the timebased navigator
     */
    val state: TimebasedNavigator.TimebasedState,

    /**
     *  Current offset in milliseconds
     */
    val currentOffset: Double?,

    /**
     *  Current buffered position in milliseconds
     */
    val currentBuffer: Long?,

    /**
     *  Current duration in milliseconds
     */
    val currentDuration: Double
) : JSONable {
    override fun toJSON(): JSONObject = JSONObject().apply {
        put("locator", locator?.toJSON())
        put("state", state.name)
        put("currentOffset", currentOffset)
        put("currentBuffer", currentBuffer)
        put("currentDuration", currentDuration)
    }
}
