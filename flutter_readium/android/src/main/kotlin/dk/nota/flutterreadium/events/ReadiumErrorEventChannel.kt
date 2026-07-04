package dk.nota.flutterreadium.events

import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.PublicationError
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
        launch {
            PluginLog.d("ReadiumError", "::sendEvent $data")
            eventSink?.success(Json.encodeToString(data))
        }
    }
}

/**
 * Structured supplementary payload for [ReadiumError.data] — a JSON object, not a
 * freeform string. All fields optional per producer; see
 * `docs/api-reference/error-codes.md`.
 */
@Serializable
data class ReadiumErrorDetails(
    val href: String? = null,
    val attempt: Int? = null,
    val maxAttempts: Int? = null,
    val httpStatus: Int? = null,
    val message: String? = null,
)

@Serializable
data class ReadiumError(
    val message: String,
    val code: String? = null,
    val data: ReadiumErrorDetails? = null,
    val stackTrace: String? = null,
) {
    companion object {
        operator fun invoke(error: PublicationError): ReadiumError =
            ReadiumError(
                message = error.message,
                code = error.errorCode.wireValue,
                data = error.cause?.message?.let { ReadiumErrorDetails(message = it) },
            )

        operator fun invoke(error: Throwable): ReadiumError =
            ReadiumError(
                message = error.message ?: error::class.simpleName ?: "Unknown error",
                code = error::class.simpleName,
                stackTrace = error.stackTraceToString(),
            )
    }
}
