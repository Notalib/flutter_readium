package dk.nota.flutter_readium.navigators

import android.os.Bundle
import kotlinx.coroutines.Job
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "Navigator"

@OptIn(ExperimentalReadiumApi::class)
abstract class Navigator(val publication: Publication, val timeBaseListener: TimeBaseListener) {
    protected val jobs = mutableListOf<Job>()

    interface TimeBaseListener {
        fun onTimebasePlaybackStateChanged(playbackState: PlaybackState)

        fun onTimebaseCurrentLocatorChanges(locator: Locator)
    }

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

    enum class PlaybackState {
        Unknown,
        Playing,
        Ready,
        Buffering,
        Failure,
    }

    fun onPlaybackStateChanged(pb: MediaNavigator.Playback) {
        var playbackState = PlaybackState.Unknown
        if (pb.state is MediaNavigator.State.Ready) {
            playbackState = if (pb.playWhenReady) PlaybackState.Playing else PlaybackState.Ready
        } else if (pb.state is MediaNavigator.State.Buffering) {
            playbackState = PlaybackState.Buffering
        } else if (pb.state is MediaNavigator.State.Failure) {
            playbackState = PlaybackState.Buffering
        }

        timeBaseListener.onTimebasePlaybackStateChanged(playbackState)
    }

    fun onCurrentLocatorChanges(locator: Locator) {
        timeBaseListener.onTimebaseCurrentLocatorChanges(locator)
    }

    /**
     * Setup listeners for the navigator
     */
    protected abstract fun setupNavigatorListeners()

    abstract fun storeState(): Bundle
}