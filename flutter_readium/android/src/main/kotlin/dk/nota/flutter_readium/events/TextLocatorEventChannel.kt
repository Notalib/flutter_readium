package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator


internal const val textLocatorEventChannelName = "dk.nota.flutter_readium/text-locator"

class TextLocatorEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Locator>(messenger, textLocatorEventChannelName) {
    override fun sendEvent(data: Locator) {
        mainScope.launch {
            eventSink?.success(data.toJSON().toString())
        }
    }
}