package dk.nota.flutter_readium.events

import dk.nota.flutter_readium.jsonEncode
import dk.nota.flutter_readium.models.ReadiumTimebasedState
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

/**
 * Event channel for sending time-based state updates to Flutter.
 */
class TimedBasedStateEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<ReadiumTimebasedState>(messenger, "dk.nota.flutter_readium/timebased-state") {
    override fun sendEvent(data: ReadiumTimebasedState) {
        mainScope.launch {
            eventSink?.success(jsonEncode(data.toJSON()))
        }
    }
}
