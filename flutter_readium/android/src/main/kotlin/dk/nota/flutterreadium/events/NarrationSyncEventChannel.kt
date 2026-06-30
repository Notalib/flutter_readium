package dk.nota.flutterreadium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

/**
 * Event channel for sending narration sync state changes to Flutter.
 * Emits `true` when narration sync is active, `false` when in manual mode.
 */
class NarrationSyncEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<Boolean>(messenger, "dk.nota.flutter_readium/narration-sync") {
    override fun sendEvent(data: Boolean) {
        launch {
            eventSink?.success(data)
        }
    }
}
