package dk.nota.flutter_readium.events

import android.util.Log
import dk.nota.flutter_readium.PublicationError
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Event channel for sending error events to Flutter.
 */
class ReadiumErrorEventChannel(
    messenger: BinaryMessenger,
) : EventChannelWrapper<ReadiumError>(messenger, "dk.nota.flutter_readium/error") {
    override fun sendEvent(data: ReadiumError) {
        mainScope.launch {
            Log.d("ReadiumError", ":sendEvent $data")
            eventSink?.success(Json.encodeToString(data))
        }
    }
}

@Serializable
data class ReadiumError(
    val message: String,
    val code: String? = null,
    val data: String? = null,
    val stackTrace: String? = null,
) {
    companion object {
        operator fun invoke(error: PublicationError): ReadiumError =
            ReadiumError(
                message = error.message,
                code = error.errorCode.name,
                data = error.cause?.message,
            )

        operator fun invoke(error: Throwable): ReadiumError =
            ReadiumError(
                message = error.message ?: error::class.simpleName ?: "Unknown error",
                code = error::class.simpleName,
                stackTrace = error.stackTraceToString(),
            )
    }
}
