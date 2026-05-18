package dk.nota.flutter_readium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.json.JSONArray
import org.json.JSONObject

/**
 * Only if if the string is not null or empty.
 */
fun String?.letIfNotEmpty(closure: (String) -> Unit) {
    if (!this.isNullOrEmpty()) closure(this)
}

/**
 * Returns null if the string is null or empty, otherwise return as is.
 */
fun String?.takeIfNotEmpty(): String? {
    if (!this.isNullOrEmpty()) return this
    return null
}

/**
 * Only [let] if both values are not null.
 */
fun <T : Any, U : Any> letIfBothNotNull(
    t: T?,
    u: U?,
): Pair<T, U>? {
    if (t == null || u == null) {
        return null
    }
    return Pair(t, u)
}

fun jsonDecode(json: String): Any = JSONArray("[$json]")[0]

/**
 * Encode object into JSON string.
 */
fun jsonEncode(json: Any?): String =
    when (json) {
        is JSONArray -> {
            json.toString()
        }

        is JSONObject -> {
            json.toString()
        }

        is Nothing? -> {
            "null"
        }

        else -> {
            val ret = JSONArray(listOf(json)).toString()
            ret.substring(1, ret.length - 1)
        }
    }

/**
 * Unwrap ContextWrapper chain to find Application
 */
fun unwrapToApplication(context: Context?): Application? {
    if (context is Application) {
        return context
    }

    if (context is Activity) {
        return context.application
    }

    var ctx = context
    while (ctx != null && ctx !is Application) {
        ctx = if (ctx is ContextWrapper) ctx.baseContext else null
    }

    if (ctx == null) {
        throw IllegalStateException("Application not found. $context")
    }
    return ctx
}

/**
 * Run a suspend block on the main dispatcher.
 */
suspend fun <T> withMainContext(block: suspend CoroutineScope.() -> T): T = withContext(Dispatchers.Main.immediate, block)

/**
 * Run a suspend block on the IO dispatcher.
 */
suspend fun <T> withIOContext(block: suspend CoroutineScope.() -> T): T = withContext(Dispatchers.IO, block)

/**
 * Turn any value into a [JsonElement]
 */
fun anyToJsonElement(value: Any?): JsonElement =
    when (value) {
        null -> JsonNull
        is Map<*, *> -> mapToJsonObject(value)
        is List<*> -> JsonArray(value.map { anyToJsonElement(it) })
        is Double -> JsonPrimitive(value)
        is Float -> JsonPrimitive(value.toDouble())
        is Number -> JsonPrimitive(value.toLong())
        is Boolean -> JsonPrimitive(value)
        is String -> JsonPrimitive(value)
        else -> JsonPrimitive(value.toString())
    }

/**
 * Turn a map into a [JsonObject]
 */
fun mapToJsonObject(map: Map<*, *>): JsonObject {
    val content =
        map.entries.associate { (k, v) ->
            val key = k?.toString() ?: "null"
            key to anyToJsonElement(v)
        }
    return JsonObject(content)
}
