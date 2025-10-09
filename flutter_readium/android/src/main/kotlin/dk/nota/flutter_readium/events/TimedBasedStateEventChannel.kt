package dk.nota.flutter_readium.events

import dk.nota.flutter_readium.jsonEncode
import dk.nota.flutter_readium.models.ReadiumTimebasedState
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

class TimedBasedStateEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<ReadiumTimebasedState>(messenger, "dk.nota.flutter_readium/timebased-state") {
    override fun sendEvent(data: ReadiumTimebasedState) {
        mainScope.launch {
            eventSink?.success(jsonEncode(data.toJSON()))
        }
    }
}
