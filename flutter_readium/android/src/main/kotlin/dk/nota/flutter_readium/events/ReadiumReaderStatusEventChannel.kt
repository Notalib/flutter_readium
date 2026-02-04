package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator

class ReadiumReaderStatusEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<ReadiumReaderStatus>(messenger, "dk.nota.flutter_readium/reader-status") {
    override fun sendEvent(data: ReadiumReaderStatus) {
        mainScope.launch {
            eventSink?.success(data.toString())
        }
    }
}

enum class ReadiumReaderStatus {
    ready,

    loading,

    closed,

    // TODO: We have no way to emit this right now.
    error,
}
