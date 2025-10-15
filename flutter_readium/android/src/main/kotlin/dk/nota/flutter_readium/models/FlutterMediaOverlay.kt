package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.getTextId
import dk.nota.flutter_readium.getTimeOffset
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import java.io.Serializable

private const val TAG = "FlutterMediaOverlay"

data class FlutterMediaOverlay(val items: List<FlutterMediaOverlayItem>) : Serializable {
    /**
     * The audio file name (without fragment).
     */
    private val audioFile = items.firstOrNull()?.audioFile ?: ""

    /**
     * The text file name (without fragment).
     */
    private val textFile = items.firstOrNull()?.textFile ?: ""

    /**
     * The audio file Url.
     */
    private val audioUrl = Url.invoke(audioFile)

    /**
     * The text file Url.
     */
    private val textUrl = Url.invoke(textFile)

    /**
     * The total duration of the audio, based on the end time of the last item.
     */
    val duration = items.lastOrNull()?.audioEnd ?: 0.0

    /**
     * Find the media overlay item for the given file and time.
     * Returns null if no item is found.
     */
    fun findItemInRange(fileHref: String, time: Double): FlutterMediaOverlayItem? {
        val href = Url.invoke(fileHref) ?: return null
        if (!href.isEquivalent(textUrl) && !href.isEquivalent(audioUrl)) {
            return null
        }

        return items.find { item -> item.isInRange(href, time) }
    }

    /**
     * Find the media overlay item from the text reference.
     */
    fun findItemFromTextId(href: Url, textId: String) : FlutterMediaOverlayItem? {
        if (!href.isEquivalent(textUrl) && !href.isEquivalent(audioUrl)) {
            return null
        }

        return items.find { item -> item.textId == textId }
    }

    /**
     * Find the media overlay item from the given locator.
     * A locator can either be an audio+time based locator or a text+id based locator.
     * This allows us to map back and forth between audio and text.
     */
    fun findItemFromLocator(locator: Locator) : FlutterMediaOverlayItem? {
        val href = locator.href
        if (!href.isEquivalent(Url.invoke(textFile)) && !href.isEquivalent(Url.invoke(audioFile))) {
            return null
        }

        locator.getTimeOffset()?.let { timeOffset ->
            return findItemInRange(href.toString(), timeOffset)
        }

        locator.getTextId()?.let { textId ->
            return findItemFromTextId(href, textId)
        }

        if (locator.locations.fragments.isEmpty() && (locator.mediaType == MediaType.HTML || locator.mediaType == MediaType.XHTML)) {
            // If there is no fragment, and it is a HTML locator, we return the first item for the href
            return items.firstOrNull { item ->
                item.textFile == href.path
            }
        }

        return null
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
