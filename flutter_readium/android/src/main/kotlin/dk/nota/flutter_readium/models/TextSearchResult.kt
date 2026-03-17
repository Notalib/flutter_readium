package dk.nota.flutter_readium.models

import org.json.JSONObject
import org.readium.r2.shared.JSONable
import org.readium.r2.shared.publication.Locator

data class TextSearchResult(
    /**
     * The locator for this search result
     */
    val locator: Locator,

    /**
     * Optional chapter title
     */
    val chapterTitle: String? = null,

    /**
     * Optional list of page numbers
     */
    val pageNumbers: List<String>? = null
) : JSONable {
    /**
     * Convert to JSON object
     */
    override fun toJSON(): JSONObject = JSONObject().apply {
        put("locator", locator.toJSON())
        put("chapterTitle", chapterTitle)
        put("pageNumbers", pageNumbers?.joinToString(","))
    }
}