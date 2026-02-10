package dk.nota.flutter_readium.events

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class ReadiumReaderStatusEventChannel(messenger: BinaryMessenger) :
    EventChannelWrapper<ReadiumReaderStatus>(messenger, "dk.nota.flutter_readium/reader-status") {
    override fun sendEvent(data: ReadiumReaderStatus) {
        mainScope.launch {
            Log.d("ReadiumReaderStatus", ":sendEvent $data")
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

    @SerialName("error")
    // TODO: We have no way to emit this right now.
    Error,
}
