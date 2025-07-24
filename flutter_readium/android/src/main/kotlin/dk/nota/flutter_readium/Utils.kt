package dk.nota.flutter_readium

import org.json.JSONArray
import org.json.JSONObject

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
