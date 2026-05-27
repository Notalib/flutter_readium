package dk.nota.flutterreadium.navigators

import android.os.Bundle
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import kotlinx.coroutines.flow.StateFlow
import org.readium.r2.shared.publication.Locator

/**
 * Common interface for all visual (page-based) navigators.
 *
 * Defines the surface used by [dk.nota.flutterreadium.ReadiumReader] and
 * [dk.nota.flutterreadium.ReadiumReaderWidget] to drive any visual navigator without
 * branching on the concrete navigator type. Navigator-specific features (e.g. EPUB
 * JavaScript evaluation, decorations, or preferences) remain on the concrete class.
 */
interface FlutterVisualNavigator {
    /** The current reading position as a live state flow. May be null before the navigator is ready. */
    val currentLocator: StateFlow<Locator?>?

    /** Initialise the navigator. Must be called once before any navigation method is used. */
    suspend fun initNavigator()

    /**
     * Navigate to [locator].
     *
     * @param animated whether the transition should be animated.
     * @param segmentDuration optional segment duration hint (seconds) for synchronized audio.
     */
    suspend fun goToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    )

    /** Navigate to the next page / resource. */
    suspend fun goForward(animated: Boolean = true)

    /** Navigate to the previous page / resource. */
    suspend fun goBackward(animated: Boolean = true)

    /** Scroll to a fractional [progression] in [0.0, 1.0] within the current resource. */
    suspend fun scrollToProgression(progression: Double)

    /** Attach the navigator fragment to the given [fragmentManager] and [viewGroup]. */
    fun attachNavigator(
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
    )

    /** Dispose the navigator and release all held resources. */
    fun dispose()

    /** Serialise the current navigator state into a [Bundle] for Android state restoration. */
    fun storeState(): Bundle
}
