package dk.nota.flutterreadium

import android.webkit.JavascriptInterface

/** Registered as `FlutterSameDocumentLinkBridge`; called by `EpubReaderFragment.injectSameDocumentLinkListener`. */
class EpubSameDocumentLinkBridge(
    private val onLink: (hash: String) -> Unit,
) {
    @JavascriptInterface
    fun onSameDocumentLink(hash: String) = onLink(hash)
}
