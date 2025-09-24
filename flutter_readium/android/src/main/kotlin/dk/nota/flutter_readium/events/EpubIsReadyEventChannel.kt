package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

internal const val isReadyChannelName = "dk.nota.flutter_readium/is-ready"

class EpubIsReadyEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Boolean>(messenger, isReadyChannelName) {
    override fun sendEvent(data: Boolean) {
        mainScope.launch {
            eventSink?.success(null)
        }
    }
}