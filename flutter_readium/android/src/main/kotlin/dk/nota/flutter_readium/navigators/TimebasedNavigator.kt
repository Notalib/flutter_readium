package dk.nota.flutter_readium.navigators

import android.util.Log
import dk.nota.flutter_readium.PublicationError
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

private const val TAG = "TimebasedNavigator"

@OptIn(ExperimentalReadiumApi::class)
abstract class TimebasedNavigator<P : MediaNavigator.Playback>(
    publication: Publication,
    val timebaseListener: TimebasedListener,
    initialLocator: Locator?
) : BaseNavigator(publication, initialLocator) {
    interface TimebasedListener {
        /**
         * Called when the playback state changes.
         */
        fun onTimebasedPlaybackStateChanged(playbackState: PlaybackState)

        /**
         * Called when there is a playback error.
         */
        fun onTimebasedPlaybackFailure(error: PublicationError)

        /**
         * Called when the current locator changes.
         */
        fun onTimebasedCurrentLocatorChanges(locator: Locator)

        /**
         * Called when there is a time-based location change, this is used to highlight text while reading.
         */
        fun onTimebasedLocationChanged(locator: Locator)
    }

    enum class PlaybackState {
        Playing,
        Ready,
        Buffering,
        Failure,
        Ended,
    }

    /**
     * Called when the playback state changes.
     */
    open fun onPlaybackStateChanged(pb: P) {
        var playbackState: PlaybackState
        when (pb.state) {
            is MediaNavigator.State.Ready -> {
                playbackState = if (pb.playWhenReady) PlaybackState.Playing else PlaybackState.Ready
            }

            is MediaNavigator.State.Buffering -> {
                playbackState = PlaybackState.Buffering
            }

            is MediaNavigator.State.Failure -> {
                playbackState = PlaybackState.Failure
            }

            is MediaNavigator.State.Ended -> {
                playbackState = PlaybackState.Ended
            }
        }

        Log.d(
            TAG,
            ": onPlaybackStateChanged: state=${pb.state} playWhenReady={${pb.playWhenReady}}, playbackState=$playbackState, index=${pb.index}"
        )

        timebaseListener.onTimebasedPlaybackStateChanged(playbackState)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        if (locator.locations.position == null) {
            val index =
                publication.readingOrder.indexOfFirst { it.href.toString() == locator.href.toString() }
            if (index != -1) {
                val newLocator = locator.copy(
                    locations = locator.locations.copy(position = index + 1)
                )
                timebaseListener.onTimebasedCurrentLocatorChanges(newLocator)
                return
            }
        }

        timebaseListener.onTimebasedCurrentLocatorChanges(locator)
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

    /**
     * Go back in the playback.
     */
    abstract fun goBack();

    /**
     * Go forward in the playback.
     */
    abstract fun goForward();
}