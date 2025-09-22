package dk.nota.flutter_readium.navigators

import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

@OptIn(ExperimentalReadiumApi::class)
abstract class TimebasedNavigator(
    publication: Publication,
    val timebasedListener: TimebasedListener,
    initialLocator: Locator?
) : Navigator(publication, initialLocator) {
    interface TimebasedListener {
        fun onTimebasedPlaybackStateChanged(playbackState: PlaybackState)

        fun onTimebasedCurrentLocatorChanges(locator: Locator)
    }

    enum class PlaybackState {
        Unknown,
        Playing,
        Ready,
        Buffering,
        Failure,
    }

    // Playback state changed
    open fun onPlaybackStateChanged(pb: MediaNavigator.Playback) {
        var playbackState = PlaybackState.Unknown
        if (pb.state is MediaNavigator.State.Ready) {
            playbackState = if (pb.playWhenReady) PlaybackState.Playing else PlaybackState.Ready
        } else if (pb.state is MediaNavigator.State.Buffering) {
            playbackState = PlaybackState.Buffering
        } else if (pb.state is MediaNavigator.State.Failure) {
            playbackState = PlaybackState.Buffering
        }

        timebasedListener.onTimebasedPlaybackStateChanged(playbackState)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        timebasedListener.onTimebasedCurrentLocatorChanges(locator)
    }

    /**
     * Start playing
     */
    open fun play() {
        play(null)
    }

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
}