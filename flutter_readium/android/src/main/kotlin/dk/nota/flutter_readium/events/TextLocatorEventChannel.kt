package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

class TextLocatorEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Locator>(messenger, "dk.nota.flutter_readium/text-locator") {
    override fun sendEvent(data: Locator) {
        mainScope.launch {
            eventSink?.success(data.toJSON().toString())
        }
    }
}
