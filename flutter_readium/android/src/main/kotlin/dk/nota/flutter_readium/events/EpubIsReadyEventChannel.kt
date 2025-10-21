package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch

/**
 * Event channel for notifying Flutter that the EPUB is ready.
 */
class EpubIsReadyEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Boolean>(messenger, "dk.nota.flutter_readium/is-ready") {
    override fun sendEvent(data: Boolean) {
        mainScope.launch {
            eventSink?.success(null)
        }
    }
}
