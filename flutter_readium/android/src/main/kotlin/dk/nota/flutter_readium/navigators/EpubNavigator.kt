package dk.nota.flutter_readium.navigators

import android.os.Bundle
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

@OptIn(ExperimentalReadiumApi::class)
class EpubNavigator(
    publication: Publication,
    initialLocator: Locator?,
) : Navigator(publication, initialLocator) {
    override suspend fun initNavigator() {
        TODO("Not yet implemented")
    }

    override fun play(fromLocator: Locator?) {
        TODO("Not yet implemented")
    }

    override fun pause() {
        TODO("Not yet implemented")
    }

    override fun resume() {
        TODO("Not yet implemented")
    }

    override fun onPlaybackStateChanged(pb: MediaNavigator.Playback) {
        TODO("Not yet implemented")
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        TODO("Not yet implemented")
    }

    override fun setupNavigatorListeners() {
        TODO("Not yet implemented")
    }

    override fun storeState(): Bundle {
        TODO("Not yet implemented")
    }
}