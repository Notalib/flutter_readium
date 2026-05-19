package dk.nota.flutter_readium.models

import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.shared.publication.Link

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
