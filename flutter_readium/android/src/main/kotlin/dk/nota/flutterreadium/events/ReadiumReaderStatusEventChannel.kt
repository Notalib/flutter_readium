package dk.nota.flutterreadium.events

import dk.nota.flutterreadium.PluginLog
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class ReadiumReaderStatusEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<ReadiumReaderStatus>(messenger, "dk.nota.flutter_readium/reader-status") {
    override fun sendEvent(data: ReadiumReaderStatus) {
        launch {
            PluginLog.d("ReadiumReaderStatus", "::sendEvent $data")
            eventSink?.success(Json.encodeToString(data))
        }
    }
}

@Serializable
enum class ReadiumReaderStatus {
    @SerialName("ready")
    Ready,

    @SerialName("loading")
    Loading,

    @SerialName("closed")
    Closed,

    // TODO: We have no way to emit this right now.
    @SerialName("error")
    Error,
}
