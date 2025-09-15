package dk.nota.flutter_readium.navigators

import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

@OptIn(ExperimentalReadiumApi::class)
abstract class TimebaseNavigator(
    publication: Publication,
    val timeBaseListener: TimeBaseListener,
    initialLocator: Locator?
) : Navigator(publication, initialLocator) {
    interface TimeBaseListener {
        fun onTimebasePlaybackStateChanged(playbackState: PlaybackState)

        fun onTimebaseCurrentLocatorChanges(locator: Locator)
    }

    enum class PlaybackState {
        Unknown,
        Playing,
        Ready,
        Buffering,
        Failure,
    }

    override fun onPlaybackStateChanged(pb: MediaNavigator.Playback) {
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

    override fun onCurrentLocatorChanges(locator: Locator) {
        timeBaseListener.onTimebaseCurrentLocatorChanges(locator)
    }
}