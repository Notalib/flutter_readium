package dk.nota.flutterreadium

import android.webkit.JavascriptInterface

/**
 * Android JavaScript interface exposed as `window.narrationSync` in the EPUB WebView.
 *
 * Allows the helper script (`NotaComicBookPage.ts`) to push narration-sync state
 * changes to native via `window.updateNarrationSync(bool)`, which is defined in
 * the bootstrap shim (see [ReadiumExtensions]) as:
 *   `window.narrationSync?.onNarrationSyncChanged(v === true)`
 *
 * Registered per-resource via [EpubReaderFragment.attachNavigator].
 */
class NarrationSyncInterface(
    private val reader: ReadiumReader,
) {
    @JavascriptInterface
    fun onNarrationSyncChanged(enabled: Boolean) {
        PluginLog.d(TAG, "::onNarrationSyncChanged enabled=$enabled")
        reader.setNarrationSyncEnabled(enabled)
    }

    companion object {
        private const val TAG = "NarrationSyncInterface"

        /** Name under which this interface is registered on the WebView window. */
        const val JS_NAME = "narrationSync"
    }
}
