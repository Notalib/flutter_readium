package dk.nota.flutter_readium.models

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.Serializable

private const val TAG = "FlutterMediaOverlay"

data class FlutterMediaOverlay(val items: List<FlutterMediaOverlayItem>) : Serializable {
    val audioFile = items.firstOrNull()?.audioFile

    val duration = items.lastOrNull()?.audioEnd ?: 0.0

    fun findItemInRange(audioIn: String, time: Double): FlutterMediaOverlayItem? {
        if (audioIn.substringBefore("#") != audioFile) {
            return null
        }

        return items.find { item -> item.isInRange(audioIn, time) }
    }

    companion object {
        fun fromJson(json: JSONObject, position: Int, title: String): FlutterMediaOverlay? {
            val topNarration = json.opt("narration") as? JSONArray ?: return null
            val role = json.optString("role")
            val items = mutableListOf<FlutterMediaOverlayItem>();
            for (i in 0 until topNarration.length()) {
                val itemJson = topNarration.getJSONObject(i)
                FlutterMediaOverlayItem.fromJson(itemJson, position, title)?.let { items.add(it) }

                fromJson(itemJson, position, title)?.let { items.addAll(it.items) }
            }

            return FlutterMediaOverlay(items)
        }
    }
}
