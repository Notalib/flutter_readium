package dk.nota.flutter_readium.models

import dk.nota.flutter_readium.cleanHref
import dk.nota.flutter_readium.ifNotEmptyLet
import dk.nota.flutter_readium.jsonDecode
import dk.nota.flutter_readium.letIfBothNotNull
import dk.nota.flutter_readium.takeIfNotEmpty
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

            physicalPage.ifNotEmptyLet {
                res["physicalPage"] = it
            }

            cssSelector.ifNotEmptyLet {
                res["cssSelector"] = it
            }

            letIfBothNotNull(tocId, href)?.let { (tocId, href) ->
                res["tocHref"] = "$href#$tocId"
            }

            return res
        }

    companion object {
        fun fromJson(json: String, href: Url): PageInformation =
            fromJson(jsonDecode(json) as JSONObject, href)

        @OptIn(InternalReadiumApi::class)
        fun fromJson(json: JSONObject, href: Url): PageInformation {
            val physicalPage = json.optNullableString("physicalPage").takeIfNotEmpty()
            val cssSelector = json.optNullableString("cssSelector").takeIfNotEmpty()
            val tocId = json.optNullableString("tocId").takeIfNotEmpty()

            return PageInformation(
                physicalPage,
                cssSelector,
                href.cleanHref().toString(),
                tocId,
            )
        }
    }
}

