package dk.nota.flutterreadium.events

import dk.nota.flutterreadium.PluginLog
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

/**
 * Event channel for playback commands received from system media controls.
 */
class ReadiumExternalPlaybackCommandEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<ReadiumExternalPlaybackCommand>(messenger, "dk.nota.flutter_readium/external-playback-command") {
    override fun sendEvent(data: ReadiumExternalPlaybackCommand) {
        launch {
            PluginLog.d("ReadiumExternalPlaybackCommand", "::sendEvent $data")
            eventSink?.success(data.toMap())
        }
    }
}

data class ReadiumExternalPlaybackCommand(
    val action: ExternalPlaybackCommandAction,
    /**
     * Requested playback position, in milliseconds, relative to the configured
     * control-panel timebase, for seek-to commands.
     */
    val position: Long? = null,
) {
    fun toMap(): Map<String, Any> =
        buildMap {
            put("action", action.wireValue)
            position?.let { put("position", it) }
        }
}

enum class ExternalPlaybackCommandAction(
    val wireValue: String,
) {
    Play("play"),
    Pause("pause"),
    SeekForward("seekForward"),
    SeekBackward("seekBackward"),
    SeekTo("seekTo"),
    Next("next"),
    Previous("previous"),
    Unknown("unknown"),
}
