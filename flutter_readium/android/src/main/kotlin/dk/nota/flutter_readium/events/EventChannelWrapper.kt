package dk.nota.flutter_readium.events

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren

abstract class EventChannelWrapper<T>(messenger: BinaryMessenger, name: String) : EventChannel.StreamHandler {
    private val eventChannel: EventChannel = EventChannel(messenger, name)
    protected var eventSink: EventChannel.EventSink? = null

    protected val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)


    init {
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?
    ) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    open fun dispose() {
        eventChannel.setStreamHandler(null)
        eventSink = null
        mainScope.coroutineContext.cancelChildren()
    }

    abstract fun sendEvent(data: T)
}

