package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.jsonDecode
import org.json.JSONObject

class PageInformation(val pageIndex: Long?, val totalPages: Long?, val physicalPageIndex: String?) {
    val otherLocations: Map<String, Any>
        get() {
            val res = mutableMapOf<String, Any>()
            if (pageIndex != null && totalPages != null) {
                res["currentPage"] = pageIndex
                res["totalPages"] = totalPages
            }

            physicalPageIndex?.takeIf { it.isNotEmpty() }?.let {
                res["physicalPage"] = it
            }
            return res;
        }

    companion object {
        fun fromJson(json: String): PageInformation = fromJson(jsonDecode(json) as JSONObject)

        fun fromJson(json: JSONObject): PageInformation {
            val pageIndex = json.optLong("pageIndex")
            val totalPages = json.optLong("totalPages")
            val physicalPageIndex = json.optString("physicalPageIndex")

            return PageInformation(pageIndex, totalPages, physicalPageIndex)
        }
    }
}
