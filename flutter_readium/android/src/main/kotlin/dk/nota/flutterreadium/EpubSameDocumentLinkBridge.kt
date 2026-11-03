package dk.nota.flutterreadium

import android.webkit.JavascriptInterface

/**
 * JavaScript interface injected into each EPUB resource WebView via
 * [org.readium.r2.navigator.epub.EpubNavigatorFragment.Configuration.registerJavascriptInterface].
 *
 * The click listener in `EpubReaderFragment.injectSameDocumentLinkListener` calls
 * `FlutterSameDocumentLinkBridge.onSameDocumentLink(hash)`. Runs on a WebView thread.
 */
class EpubSameDocumentLinkBridge(
    private val onLink: (hash: String) -> Unit,
) {
    @JavascriptInterface
    fun onSameDocumentLink(hash: String) = onLink(hash)
}
