package dk.nota.flutter_readium.models

import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * A Readium Guided Navigation Document, describing a structured sequence of
 * media-aligned navigation steps for a publication.
 *
 * See https://readium.org/guided-navigation/schema/document.schema.json
 */
data class GuidedNavigationDocument(
    /** The ordered list of guided navigation objects. Contains at least one entry. */
    val guided: List<GuidedNavigationObject>,
    /**
     * Optional cross-references to related resources, using the Readium Web
     * Publication Manifest link schema.
     */
    val links: List<Link> = emptyList(),
) {
    fun toJSON(): JSONObject =
        JSONObject().apply {
            if (links.isNotEmpty()) {
                put("links", JSONArray(links.map { it.toJSON() }))
            }
            put("guided", JSONArray(guided.map { it.toJSON() }))
        }

    fun toJSONString(): String = toJSON().toString()

    companion object {
        fun fromJSON(json: JSONObject?): GuidedNavigationDocument? {
            if (json == null) return null

            val linksArray = json.optJSONArray("links")
            val links =
                buildList {
                    if (linksArray != null) {
                        for (i in 0 until linksArray.length()) {
                            linksArray
                                .optJSONObject(i)
                                ?.let { Link.fromJSON(it) }
                                ?.let { add(it) }
                        }
                    }
                }

            val guided = GuidedNavigationObject.fromJSONArray(json.optJSONArray("guided"))
            if (guided.isEmpty()) return null

            return GuidedNavigationDocument(guided = guided, links = links)
        }

        fun fromJSON(jsonString: String): GuidedNavigationDocument? = fromJSON(JSONObject(jsonString))
    }
}

val guidedNavigationMediaType = MediaType("application/guided-navigation+json")

/**
 * Converts this document to a list of [FlutterMediaOverlay] by flattening all
 * [GuidedNavigationObject]s that carry both an [audioref] and a [textref], then
 * grouping the resulting items by their (audioFile, textFile) pair.
 *
 * @param position    Reading-order position (1-based) shared by all generated items.
 * @param tocHref     ToC href to attach to every item, or null if unknown.
 * @param title       Fallback chapter/section title. Overridden by each object's own text if present.
 * @param readiumOrderItemDuration  Total duration of the reading-order item, used for progression calculations.
 */
fun GuidedNavigationDocument.toMediaOverlays(
    position: Int = 0,
    tocHref: Url? = null,
    title: String = "",
    readiumOrderItemDuration: Double = 0.0,
): List<FlutterMediaOverlay> {
    fun GuidedNavigationObject.flatten(): List<FlutterMediaOverlayItem> {
        val items = mutableListOf<FlutterMediaOverlayItem>()
        if (audioref != null && textref != null) {
            items +=
                FlutterMediaOverlayItem(
                    audio = audioref,
                    text = textref,
                    position = position,
                    tocHref = tocHref,
                    title = title,
                    readingOrderItemDuration = readiumOrderItemDuration,
                )
        }
        children.forEach { items += it.flatten() }
        return items
    }

    val allItems = guided.flatMap { it.flatten() }

    // Group by (audioFile, textFile), preserving insertion order.
    val orderedKeys = mutableListOf<Pair<String, String>>()
    val itemsByKey = linkedMapOf<Pair<String, String>, MutableList<FlutterMediaOverlayItem>>()
    for (item in allItems) {
        val key = item.audioFile to item.textFile
        itemsByKey
            .getOrPut(key) {
                orderedKeys.add(key)
                mutableListOf()
            }.add(item)
    }

    return orderedKeys.map { key -> FlutterMediaOverlay(itemsByKey.getValue(key)) }
}
