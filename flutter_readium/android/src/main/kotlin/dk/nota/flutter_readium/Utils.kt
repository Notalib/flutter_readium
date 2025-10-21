package dk.nota.flutter_readium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.html.domRange

inline fun <T : Any> guardLet(vararg elements: T?, closure: () -> Nothing): List<T> {
    return if (elements.all { it != null }) {
        elements.filterNotNull()
    } else {
        closure()
    }
}

inline fun <T : Any> ifLet(vararg elements: T?, closure: (List<T>) -> Unit) {
    if (elements.all { it != null }) {
        closure(elements.filterNotNull())
    }
}

fun <T : Any, U : Any> letIfBothNotNull(t: T?, u: U?): Pair<T, U>? {
    if (t == null || u == null) {
        return null
    }
    return Pair(t, u)
}


fun jsonDecode(json: String): Any = JSONArray("[$json]")[0]

fun jsonEncode(json: Any?): String = when (json) {
    is JSONArray -> json.toString()
    is JSONObject -> json.toString()
    is Nothing? -> "null"
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
 * Check if a Locator has scrollable locations.
 */
fun canScroll(locations: Locator.Locations) =
    locations.domRange != null || locations.cssSelector != null || locations.progression != null

/**
 * Run a suspend block with the given CoroutineScope's context.
 */
 suspend fun <T> withScope(
    scope:  CoroutineScope,
    block: suspend CoroutineScope.() -> T
): T {
    return withContext(scope.coroutineContext, block)
}

/**
 * Update the value of a MutableStateFlow only if it is different from the current value.
 */
fun <T> MutableStateFlow<T>.update(new: T) {
    if (this.value != new) this.value = new
}
