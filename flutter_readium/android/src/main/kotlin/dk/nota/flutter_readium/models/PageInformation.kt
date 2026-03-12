package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.cleanHref
import dk.nota.flutter_readium.jsonDecode
import org.json.JSONObject
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.extensions.optNullableString
import org.readium.r2.shared.util.Url

class PageInformation(
    val physicalPage: String?,
    val cssSelector: String?,
    val href: String,
    val tocId: String?,
) {
    val otherLocations: Map<String, Any>
        get() {
            val res = mutableMapOf<String, Any>()

            physicalPage?.takeIf { it.isNotEmpty() }?.let {
                res["physicalPage"] = it
            }

            cssSelector?.takeIf { it.isNotEmpty() }?.let {
                res["cssSelector"] = it
            }

            tocId?.takeIf { it.isNotEmpty() }?.let {
                res["tocHref"] = "$href#$tocId"
            }

            return res;
        }

    companion object {
        fun fromJson(json: String, href: Url): PageInformation =
            fromJson(jsonDecode(json) as JSONObject, href)

        @OptIn(InternalReadiumApi::class)
        fun fromJson(json: JSONObject, href: Url): PageInformation {
            val physicalPage = json.optString("physicalPage").takeIf { it.isNotEmpty() }
            val cssSelector = json.optNullableString("cssSelector")
            val tocId = json.optNullableString("tocId")?.takeIf { it.isNotEmpty() }

            return PageInformation(
                physicalPage,
                cssSelector,
                href.cleanHref().toString(),
                tocId,
            )
        }
    }
}
