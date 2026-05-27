package dk.nota.flutterreadium.events

import dk.nota.flutterreadium.jsonEncode
import dk.nota.flutterreadium.models.ReadiumTimebasedState
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

/**
 * Event channel for sending time-based state updates to Flutter.
 */
class TimedBasedStateEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<ReadiumTimebasedState>(messenger, "dk.nota.flutter_readium/timebased-state") {
    override fun sendEvent(data: ReadiumTimebasedState) {
        launch {
            eventSink?.success(jsonEncode(data.toJSON()))
        }
    }
}
