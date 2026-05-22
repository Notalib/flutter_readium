package dk.nota.flutter_readium

import android.util.Log

// Log levels matching the Dart LogLevel enum (index order: none=0, error=1, warn=2, info=3, debug=4)
internal enum class PluginLogLevel(val value: Int) {
    NONE(0),
    ERROR(1),
    WARN(2),
    INFO(3),
    DEBUG(4),
}

internal object PluginLog {
    var level: PluginLogLevel = PluginLogLevel.INFO

    fun e(
        tag: String,
        message: String,
    ) {
        if (level.value >= PluginLogLevel.ERROR.value) Log.e(tag, message)
    }

    fun e(
        tag: String,
        message: String,
        throwable: Throwable,
    ) {
        if (level.value >= PluginLogLevel.ERROR.value) Log.e(tag, message, throwable)
    }

    fun w(
        tag: String,
        message: String,
    ) {
        if (level.value >= PluginLogLevel.WARN.value) Log.w(tag, message)
    }

    fun i(
        tag: String,
        message: String,
    ) {
        if (level.value >= PluginLogLevel.INFO.value) Log.i(tag, message)
    }

    fun d(
        tag: String,
        message: String,
    ) {
        if (level.value >= PluginLogLevel.DEBUG.value) Log.d(tag, message)
    }
}
