package dk.nota.flutterreadium.models

import dk.nota.flutterreadium.navigators.TimebasedNavigator
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
    /**
     *  Current offset in publication timeline, in milliseconds.
     */
    val totalProgressDuration: Double? = null,
    /**
     *  Total duration of the publication, in milliseconds.
     */
    val totalDuration: Double? = null,
) : JSONable {
    fun copyWith(
        state: TimebasedNavigator.TimebasedState = this.state,
        currentLocator: Locator? = this.currentLocator,
        currentOffset: Double? = this.currentOffset,
        currentBuffered: Long? = this.currentBuffered,
        currentDuration: Double? = this.currentDuration,
        totalProgressDuration: Double? = this.totalProgressDuration,
        totalDuration: Double? = this.totalDuration,
    ): ReadiumTimebasedState {
        if (state == this.state && currentLocator == this.currentLocator && currentOffset == this.currentOffset &&
            currentBuffered == this.currentBuffered &&
            currentDuration == this.currentDuration &&
            totalProgressDuration == this.totalProgressDuration &&
            totalDuration == this.totalDuration
        ) {
            // No changes, return this to avoid StateFlow triggering updates.
            return this
        }

        return ReadiumTimebasedState(
            state,
            currentLocator,
            currentOffset,
            currentBuffered,
            currentDuration,
            totalProgressDuration,
            totalDuration,
        )
    }

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
            putOpt("totalProgressDuration", totalProgressDuration)
            putOpt("totalDuration", totalDuration)
        }

    companion object {
        fun none(): ReadiumTimebasedState = ReadiumTimebasedState()
    }
}
