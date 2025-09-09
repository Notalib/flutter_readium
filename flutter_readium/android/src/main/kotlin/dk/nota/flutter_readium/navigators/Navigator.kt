package dk.nota.flutter_readium.navigators

import org.readium.r2.shared.publication.Locator

interface Navigator {
    /**
     * Init the navigator
     */
    suspend fun initNavigator(): Unit

    /**
     * Start playing. If fromLocator is provided from that position.
     */
    fun play(fromLocator: Locator?)

    /**
     * Start playing
     */
    fun play()

    /**
     * Pause playback.
     */
    fun pause(): Unit

    /**
     * Resume playback
     */
    fun resume(): Unit
}