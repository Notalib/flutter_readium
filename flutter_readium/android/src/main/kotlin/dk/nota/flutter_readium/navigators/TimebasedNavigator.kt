package dk.nota.flutter_readium.navigators

import android.util.Log
import dk.nota.flutter_readium.PublicationError
import kotlinx.coroutines.async
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.positions
import kotlin.time.Duration

private const val TAG = "TimebasedNavigator"

/**
 * Base class for time-based navigators, such as audiobook or TTS navigators.
 */
@OptIn(ExperimentalReadiumApi::class)
abstract class TimebasedNavigator<P : MediaNavigator.Playback>(
    publication: Publication,

    /**
     * Listener for time-based navigator events.
     */
    protected val timebaseListener: TimebasedListener,
    initialLocator: Locator?
) : BaseNavigator(publication, initialLocator) {
    var isPlaying = false

    /**
     * Listener interface for time-based navigator events.
     */
    interface TimebasedListener {
        /**
         * Called when the playback state changes.
         */
        fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedState)

        /**
         * Called when the time-based buffer changes.
         */
        fun onTimebasedBufferChanged(buffer: Duration?)

        /**
         * Called when there is a playback error.
         */
        fun onTimebasedPlaybackFailure(error: PublicationError)

        /**
         * Called when the current locator changes.
         */
        fun onTimebasedCurrentLocatorChanges(locator: Locator, currentReadingOrderLink: Link?)

        /**
         * Called when there is a time-based location change, this is used to highlight text while reading.
         */
        fun onTimebasedLocationChanged(locator: Locator)
    }

    // Possible states for a time-based navigator.
    enum class TimebasedState {
        Playing,

        Paused,

        Loading,

        Failure,

        Ended,
    }

    /**
     * Called when the playback state changes.
     */
    open fun onPlaybackStateChanged(pb: P) {
        var timebasedState: TimebasedState
        when (pb.state) {
            is MediaNavigator.State.Ready -> {
                timebasedState =
                    if (pb.playWhenReady) TimebasedState.Playing else TimebasedState.Paused
            }

            is MediaNavigator.State.Buffering -> {
                timebasedState = TimebasedState.Loading
            }

            is MediaNavigator.State.Failure -> {
                timebasedState = TimebasedState.Failure
            }

            is MediaNavigator.State.Ended -> {
                timebasedState = TimebasedState.Ended
            }
        }

        Log.d(
            TAG,
            ": onPlaybackStateChanged: state=${pb.state} playWhenReady={${pb.playWhenReady}}, playbackState=$timebasedState, index=${pb.index}"
        )

        isPlaying = timebasedState == TimebasedState.Playing

        timebaseListener.onTimebasedPlaybackStateChanged(timebasedState)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        var emittingLocator = locator

        val readingOrderLink =
            publication.readingOrder.find { link ->
                link.href.toString() == locator.href.toString()
            }

        if (emittingLocator.locations.position == null) {
            publication.readingOrder.indexOfFirst { link ->
                link == readingOrderLink
            }.takeIf { it > -1 }?.let { index ->
                emittingLocator = emittingLocator.copy(
                    locations = locator.locations.copy(position = index + 1)
                )
            }
        }

        timebaseListener.onTimebasedCurrentLocatorChanges(emittingLocator, readingOrderLink)
    }

    /**
     * Start playing
     */
    open suspend fun play() {
        play(null)
    }

    /**
     * Start playing. If fromLocator is provided from that position.
     */
    abstract suspend fun play(fromLocator: Locator?)

    /**
     * Pause playback.
     */
    abstract suspend fun pause()

    /**
     * Resume playback
     */
    abstract suspend fun resume()

    /**
     * Go back in the playback.
     */
    abstract suspend fun goBackward()

    /**
     * Go forward in the playback.
     */
    abstract suspend fun goForward()

    /**
     * Seek to a specific position in the playback.
     */
    abstract suspend fun goToLocator(locator: Locator)

    /**
     * Seek to a specific offset in seconds from the current position. Can be negative or positive.
     */
    abstract suspend fun seekTo(offset: Double)
}
