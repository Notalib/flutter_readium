package dk.nota.flutter_readium.models

import android.util.Log
import kotlinx.serialization.Serializable
import org.json.JSONArray
import org.json.JSONObject

private const val TAG = "FlutterMediaOverlay"

@Serializable
class FlutterMediaOverlay(val items: List<FlutterMediaOverlayItem>) {
    companion object {
        fun fromJson(json: JSONObject): FlutterMediaOverlay? {
            val topNarration = json.opt("narration") as? JSONArray ?: return null
            val role = json.optString("role")
            val items = mutableListOf<FlutterMediaOverlayItem>();
            for (i in 0 until topNarration.length()) {
                val itemJson = topNarration.getJSONObject(i)
                FlutterMediaOverlayItem.fromJson((itemJson))?.let { items.add(it) }

                fromJson(itemJson)?.let { items.addAll(it.items) }
            }

            return FlutterMediaOverlay(items)
        }
    }
}
