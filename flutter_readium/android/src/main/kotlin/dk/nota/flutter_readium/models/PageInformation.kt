package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.jsonDecode
import org.json.JSONObject

class PageInformation(
    val page: Long?,
    val totalPages: Long?,
    val physicalPage: String?,
    val cssSelector: String?
) {
    val otherLocations: Map<String, Any>
        get() {
            val res = mutableMapOf<String, Any>()
            if (page != null && totalPages != null) {
                res["currentPage"] = page
                res["totalPages"] = totalPages
            }

            physicalPage?.takeIf { it.isNotEmpty() }?.let {
                res["physicalPage"] = it
            }

            cssSelector?.takeIf { it.isNotEmpty() }?.let {
                res["cssSelector"] = it
            }
            return res;
        }

    companion object {
        fun fromJson(json: String): PageInformation = fromJson(jsonDecode(json) as JSONObject)

        fun fromJson(json: JSONObject): PageInformation {
            val page = json.optLong("page")
            val totalPages = json.optLong("totalPages")
            val physicalPage = json.optString("physicalPage").takeIf {it.isNotEmpty()}
            val cssSelector = json.optString("cssSelector")

            return PageInformation(page, totalPages, physicalPage, cssSelector)
        }
    }
}
