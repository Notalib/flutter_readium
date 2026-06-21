package dk.nota.flutterreadium

import android.webkit.JavascriptInterface
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.json.JSONObject
import java.net.URI

private const val TAG = "EpubImageTapBridge"

/**
 * JavaScript interface injected into each EPUB resource WebView via
 * [org.readium.r2.navigator.epub.EpubNavigatorFragment.Configuration.registerJavascriptInterface].
 *
 * Exposes a single entry point callable from content JS:
 * `FlutterImageBridge.onImageTapped(JSON.stringify(payload))`
 *
 * The bridge resolves the publication-relative href from the absolute `img.src`
 * URL by suffix-matching the path component against all known publication links.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EpubImageTapBridge {
    @JavascriptInterface
    fun onImageTapped(json: String) {
        val channel =
            ReadiumReader.currentReaderWidget?.channel ?: run {
                PluginLog.w(TAG, "::onImageTapped. No reader channel available.")
                return
            }
        try {
            val data = JSONObject(json)
            val srcUrl = data.optString("srcUrl")
            val href =
                resolvePublicationHref(srcUrl) ?: run {
                    PluginLog.w(TAG, "::onImageTapped. Could not resolve href for srcUrl=$srcUrl")
                    return
                }

            val result =
                JSONObject().apply {
                    put("href", href)
                    val alt = data.optString("alt").ifEmpty { null }
                    if (alt != null) put("alt", alt)
                    val rectData = data.optJSONObject("rect")
                    if (rectData != null) put("rect", rectData)
                    val nw = data.optInt("nw").takeIf { it > 0 }
                    val nh = data.optInt("nh").takeIf { it > 0 }
                    if (nw != null) put("pixelWidth", nw)
                    if (nh != null) put("pixelHeight", nh)
                }

            PluginLog.d(TAG, "::onImageTapped href=$href")
            channel.onImageTapped(result.toString())
        } catch (e: Exception) {
            PluginLog.w(TAG, "::onImageTapped. Failed to process event: $e")
        }
    }

    private fun resolvePublicationHref(srcUrl: String): String? {
        if (srcUrl.isEmpty()) return null
        val publication = ReadiumReader.currentPublication ?: return null
        return try {
            val imgPath = URI(srcUrl).path
            val allLinks = publication.readingOrder + publication.resources
            allLinks
                .find { link ->
                    val linkHref = link.href.toString()
                    imgPath.endsWith("/$linkHref") || imgPath == linkHref
                }?.href
                ?.toString()
                ?: imgPath.trimStart('/')
        } catch (e: Exception) {
            PluginLog.w(TAG, "::resolvePublicationHref. URI parse failed for srcUrl=$srcUrl: $e")
            null
        }
    }
}
