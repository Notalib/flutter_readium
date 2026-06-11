package dk.nota.flutterreadium.models

import dk.nota.flutterreadium.cleanHref
import dk.nota.flutterreadium.jsonDecode
import dk.nota.flutterreadium.letIfBothNotNull
import dk.nota.flutterreadium.letIfNotEmpty
import dk.nota.flutterreadium.takeIfNotEmpty
import org.json.JSONObject
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.extensions.optNullableString
import org.readium.r2.shared.util.Url

/**
 * Page information from the webview.
 *
 * Retrieved via window.flutterReadium.getPageInformation().
 *
 * Requires injection of Table Of Content ids into javascript.
 * Either into windows.readiumTocIDs = [...] or by calling
 * window.flutterReadium.registerToc([...]);
 */
class PageInformation(
    /**
     * Physical page information, usually an integer as a string, but can be in other formats.
     */
    val physicalPage: String?,
    /**
     * First visible cssSelector. Can be any valid cssSelector.
     */
    val cssSelector: String?,
    /**
     * Href for the current file, not retrieved from javascript.
     */
    val href: String,
    /**
     * Current ToC id.
     */
    val tocId: String?,
) {
    val otherLocations: Map<String, Any>
        get() {
            val res = mutableMapOf<String, Any>()

            physicalPage.letIfNotEmpty {
                res["physicalPage"] = it
            }

            cssSelector.letIfNotEmpty {
                res["cssSelector"] = it
            }

            letIfBothNotNull(tocId, href)?.let { (tocId, href) ->
                res["tocHref"] = "$href#$tocId"
            }

            return res
        }

    companion object {
        /**
         * Parse JSON string from window.flutterReadium.getPageInformation()
         */
        fun fromJson(
            json: String,
            href: Url,
        ): PageInformation = fromJson(jsonDecode(json) as JSONObject, href)

        /**
         * Parse JSON object from window.flutterReadium.getPageInformation()
         */
        @OptIn(InternalReadiumApi::class)
        fun fromJson(
            json: JSONObject,
            href: Url,
        ): PageInformation {
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
