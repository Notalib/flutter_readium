package dk.nota.flutterreadium

import android.os.Bundle
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@OptIn(ExperimentalCoroutinesApi::class)
@androidx.annotation.OptIn(UnstableApi::class)
internal class PluginMediaServiceTest {
    private lateinit var callback: PluginMediaService
    private lateinit var player: ExoPlayer
    private lateinit var session: MediaSession

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication()
        callback = PluginMediaService()
        player = ExoPlayer.Builder(context).build()
        session = MediaSession.Builder(context, player).setCallback(callback).build()
    }

    @After
    fun tearDown() {
        session.release()
        player.release()
    }

    @Test
    fun connectedControllerReceivesPlaybackAndCustomCommands() {
        val future = MediaController.Builder(RuntimeEnvironment.getApplication(), session.token).buildAsync()
        shadowOf(Looper.getMainLooper()).idle()
        val controller = future.get(10, TimeUnit.SECONDS)
        try {
            assertTrue(controller.isCommandAvailable(Player.COMMAND_GET_TIMELINE))
            assertTrue(controller.isCommandAvailable(Player.COMMAND_PLAY_PAUSE))
            NotificationPlayerCustomCommandButton.entries.forEach { button ->
                assertTrue(controller.availableSessionCommands.contains(button.commandButton.sessionCommand!!))
            }
        } finally {
            controller.release()
        }
    }

    @Test
    fun untrustedControllerRetainsDefaultPlayerCommands() {
        val controller =
            MediaSession.ControllerInfo.createTestOnlyControllerInfo(
                "other.app",
                1,
                2,
                0,
                0,
                false,
                Bundle.EMPTY,
                true,
            )
        val result = callback.onConnectAsync(session, controller).get(10, TimeUnit.SECONDS)

        assertTrue(result.isAccepted)
        assertEquals(MediaSession.ConnectionResult.DEFAULT_UNTRUSTED_PLAYER_COMMANDS, result.availablePlayerCommands)
        assertTrue(result.availablePlayerCommands.contains(Player.COMMAND_GET_TIMELINE))
        assertFalse(result.availablePlayerCommands.contains(Player.COMMAND_PLAY_PAUSE))
    }
}
