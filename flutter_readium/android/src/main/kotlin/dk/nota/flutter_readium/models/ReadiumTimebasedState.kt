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
     *  Current state of the timebased navigator
     */
    val state: TimebasedNavigator.TimebasedState = TimebasedNavigator.TimebasedState.None,
    /**
     * Current timebased locator
     */
    val currentLocator: Locator? = null,
    /**
     *  Current offset in milliseconds
     */
    val currentOffset: Double? = null,
    /**
     *  Current buffered position in milliseconds
     */
    val currentBuffered: Long? = null,
    /**
     *  Current duration in milliseconds
     */
    val currentDuration: Double? = null,
) : JSONable {
    /**
     * Convert to JSON object
     */
    override fun toJSON(): JSONObject =
        JSONObject().apply {
            put("currentLocator", currentLocator?.toJSON())
            put("state", state.name)
            putOpt("currentOffset", currentOffset)
            putOpt("currentBuffered", currentBuffered)
            putOpt("currentDuration", currentDuration)
        }
}
