package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren

/**
 * A wrapper around EventChannel to simplify event sending from Kotlin to Flutter.
 *
 * @param T The type of data to be sent through the event channel.
 * @param messenger The BinaryMessenger used to create the EventChannel.
 * @param name The name of the EventChannel.
 */
abstract class EventChannelWrapper<T>(
    messenger: BinaryMessenger,
    name: String,
) : EventChannel.StreamHandler,
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) {
    private val eventChannel: EventChannel = EventChannel(messenger, name)
    protected var eventSink: EventChannel.EventSink? = null

    init {
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    open fun dispose() {
        eventChannel.setStreamHandler(null)
        eventSink = null
        coroutineContext.cancelChildren()
    }

    /**
     * Sends an event with the given data.
     */
    abstract fun sendEvent(data: T)
}
