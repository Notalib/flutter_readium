package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

class EpubIsReadyEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Boolean>(messenger, "dk.nota.flutter_readium/is-ready") {
    override fun sendEvent(data: Boolean) {
        mainScope.launch {
            eventSink?.success(null)
        }
    }
}
