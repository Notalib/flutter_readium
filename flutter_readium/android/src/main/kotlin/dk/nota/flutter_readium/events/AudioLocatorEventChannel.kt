package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

internal const val audioLocatorChannelName = "dk.nota.flutter_readium/audio-locator"
class AudioLocatorEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<Locator>(messenger, audioLocatorChannelName) {
    override fun sendEvent(data: Locator) {
        mainScope.launch {
            eventSink?.success(data.toJSON().toString())
        }
    }
}

