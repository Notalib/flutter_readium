package dk.nota.flutter_readium.navigators

import android.util.Log
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "TimebasedNavigator"

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
        } else if (pb.state is MediaNavigator.State.Failure) {
            playbackState = PlaybackState.Failure
        }

        Log.d(
            TAG,
            ": onPlaybackStateChanged: state=${pb.state} playWhenReady={${pb.playWhenReady}}, playbackState=$playbackState, index=${pb.index}"
        )

        timebasedListener.onTimebasedPlaybackStateChanged(playbackState)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        Log.d(TAG, ": onCurrentLocatorChanges: $locator")
        if (locator.locations.position == null) {
            val index =
                publication.readingOrder.indexOfFirst { it.href.toString() == locator.href.toString() }
            if (index != -1) {
                val newLocator = locator.copy(
                    locations = locator.locations.copy(position = index + 1)
                )
                timebasedListener.onTimebasedCurrentLocatorChanges(newLocator)
                return
            }
        }

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