package dk.nota.flutter_readium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

inline fun <T : Any> guardLet(
    vararg elements: T?,
    closure: () -> Nothing,
): List<T> =
    if (elements.all { it != null }) {
        elements.filterNotNull()
    } else {
        closure()
    }

inline fun <T : Any> ifLet(
    vararg elements: T?,
    closure: (List<T>) -> Unit,
) {
    if (elements.all { it != null }) {
        closure(elements.filterNotNull())
    }
}

fun String?.ifNotEmptyLet(closure: (String) -> Unit) {
    if (this != null && this.isNotEmpty()) closure(this)
}

fun String?.takeIfNotEmpty(): String? {
    if (this != null && this.isNotEmpty()) return this
    return null
}

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

// Unwrap ContextWrapper chain to find Application
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
 * Run a suspend block with the given CoroutineScope's context.
 */
suspend fun <T> withScope(
    scope: CoroutineScope,
    block: suspend CoroutineScope.() -> T,
): T = withContext(scope.coroutineContext, block)

/**
 * Update the value of a MutableStateFlow only if it is different from the current value.
 */
fun <T> MutableStateFlow<T>.update(new: T) {
    if (this.value != new) this.value = new
}

@Throws(JSONException::class)
fun JSONArray.toList(): List<Any> {
    val list = mutableListOf<Any>()
    for (i in 0 until this.length()) {
        list.add(this[i])
    }
    return list
}

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

fun mapToJsonObject(map: Map<*, *>): JsonObject {
    val content =
        map.entries.associate { (k, v) ->
            val key = k?.toString() ?: "null"
            key to anyToJsonElement(v)
        }
    return JsonObject(content)
}
