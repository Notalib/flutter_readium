package dk.nota.flutter_readium.navigators

import android.os.Bundle
import kotlinx.coroutines.Job
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "Navigator"

@OptIn(ExperimentalReadiumApi::class)
abstract class Navigator(
    val publication: Publication,
    val initialLocator: Locator?
) {
    protected val jobs = mutableListOf<Job>()

    /**
     * Start playing
     */
    open fun play() {
        play(null)
    }

    /**
     * Init the navigator
     */
    abstract suspend fun initNavigator()

    /**
     * Start playing. If fromLocator is provided from that position.
     */
    abstract fun play(fromLocator: Locator?)

    /**
     * Pause playback.
     */
    abstract fun pause()

    /**
     * Resume playback
     */
    abstract fun resume()

    open fun dispose() {
        jobs.forEach { it.cancel() }
        jobs.clear()
    }

    abstract fun onPlaybackStateChanged(pb: MediaNavigator.Playback)

    abstract fun onCurrentLocatorChanges(locator: Locator)

    /**
     * Setup listeners for the navigator
     */
    protected abstract fun setupNavigatorListeners()

    abstract fun storeState(): Bundle
}

