package dk.nota.flutterreadium

import android.content.Context
import android.graphics.Color
import android.util.AttributeSet
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.LinearLayout.generateViewId
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.commitNow
import dk.nota.flutterreadium.events.ReadiumError
import dk.nota.flutterreadium.events.ReadiumReaderStatus
import dk.nota.flutterreadium.fragments.EpubReaderFragment
import dk.nota.flutterreadium.fragments.PdfReaderFragment
import dk.nota.flutterreadium.models.PageInformation
import dk.nota.flutterreadium.navigators.EpubNavigator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "ReadiumReaderView"
internal const val VIEW_TYPE_CHANNEL_NAME = "dk.nota.flutter_readium/ReadiumReaderWidget"

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class ReadiumReaderWidget(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>,
    messenger: BinaryMessenger,
    attrs: AttributeSet? = null,
) : PlatformView,
    MethodChannel.MethodCallHandler,
    EpubReaderFragment.Listener,
    PdfReaderFragment.Listener,
    EpubNavigator.VisualListener,
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) {
    internal val channel: ReadiumReaderChannel

    /**
     * Make sure we only sent ready status once.
     */
    var hasSentReady = false

    private val layout: ViewGroup

    // Source the host activity from the plugin's ActivityAware binding (via ReadiumReader),
    // not the PlatformView's view context. The view context is the Activity only under
    // Texture-Layer Hybrid Composition; under Hybrid Composition it is a non-Activity context
    // and casting it throws ClassCastException.
    private val activity: FragmentActivity
        get() =
            ReadiumReader.fragmentActivity
                ?: throw IllegalStateException(
                    "::activity. No FragmentActivity available — is the plugin attached to a FragmentActivity host?",
                )
    private val fragmentManager
        get() = activity.supportFragmentManager

    override fun getView(): View {
        // PluginLog.d(TAG, "::getView")
        return layout
    }

    override fun dispose() {
        PluginLog.d(TAG, "::dispose")
        ReadiumReader.visualClose()

        ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Closed)
        hasSentReady = false

        channel.setMethodCallHandler(null)

        coroutineContext.cancelChildren()
        layout.removeAllViews()
    }

    override fun onFlutterViewAttached(flutterView: View) {
        // Seems to never be called, so can't use this. Flutter bug?
        PluginLog.d(TAG, "::onFlutterViewAttached")
        super.onFlutterViewAttached(flutterView)
    }

    override fun onFlutterViewDetached() {
        // Seems to never be called, so can't use this. Flutter bug?
        PluginLog.d(TAG, "::onFlutterViewDetached")
        super.onFlutterViewDetached()
    }

    init {
        PluginLog.d(TAG, "::init")

        @Suppress("UNCHECKED_CAST")
        val initPrefsMap =
            creationParams["preferences"] as Map<String, String>?
        val publication = ReadiumReader.currentPublication
        val locatorString = creationParams["initialLocator"] as String?
        val allowScreenReaderNavigation = creationParams["allowScreenReaderNavigation"] as Boolean?

        // Accepted for API parity with iOS but currently no-op: kotlin-toolkit's
        // EpubNavigatorFragment.Configuration does not expose preload-count fields
        // (preload is governed by an internal R2ViewPager.offscreenPageLimit). Revisit
        // when upstream adds a public knob.
        @Suppress("UNUSED_VARIABLE")
        val preloadPreviousPositionCount = creationParams["preloadPreviousPositionCount"] as Int?

        @Suppress("UNUSED_VARIABLE")
        val preloadNextPositionCount = creationParams["preloadNextPositionCount"] as Int?
        val initialLocator =
            if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)

        val initialPreferences =
            initPrefsMap?.let { FlutterEpubPreferences.fromMap(it) } ?: FlutterEpubPreferences()

        PluginLog.d(TAG, "publication = $publication")

        layout = LinearLayout(context, attrs)
        layout.id = generateViewId()
        layout.setBackgroundColor(Color.TRANSPARENT)
        layout.setPadding(0, 0, 0, 0)

        ReadiumReader.currentReaderWidget = this

        channel = ReadiumReaderChannel(messenger, "$VIEW_TYPE_CHANNEL_NAME:$id")
        channel.setMethodCallHandler(this)

        ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Loading)

        hasSentReady = false

        // By default reader contents are hidden from screen-readers, as not to trap them within it.
        // This can be toggled back on via the 'allowScreenReaderNavigation' creation param.
        // See issue: https://notalib.atlassian.net/browse/NOTA-9828
        if (allowScreenReaderNavigation != true) {
            layout.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        // Remove existing fragment if any (this is to avoid crashing on restore).
        // Cast as base Fragment so we strip either reader type cleanly.
        fragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG)?.let { fragment ->
            PluginLog.d(TAG, "::init - remove existing fragment")
            fragmentManager.commitNow {
                remove(fragment)
            }
        }

        launch {
            try {
                ReadiumReader.visualEnable(
                    initialLocator,
                    initialPreferences,
                    fragmentManager,
                    layout,
                    this@ReadiumReaderWidget,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PluginLog.e(TAG, "::init - visualEnable failed: ${e.message}", e)
                ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Error)
                ReadiumReader.emitError(ReadiumError(e))
            }
        }
    }

    override fun onPageLoaded() {
        PluginLog.d(TAG, "::onPageLoaded")
    }

    // To avoid duplicate onPageChanged events.
    private var lastPageLoadedKey: String? = null

    // Some navigator transitions update currentLocator without a page-changed callback.
    // Mirror those into the text-locator stream once so Flutter can observe progress.
    private var lastVisualLocationKey: String? = null

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        val currentKey = "${locator.href}@${locator.progression}"
        PluginLog.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.progression} ${locator.locations}",
        )

        if (lastPageLoadedKey == currentKey) {
            // Sometimes we get duplicate calls to onPageChanged with same locator.
            // Not sure why, but ignore them.
            return
        }

        lastPageLoadedKey = currentKey

        launch {
            if (!hasSentReady) {
                hasSentReady = true

                ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Ready)
            }

            emitOnPageChanged(pageIndex, totalPages, locator)

            // Re-inject MO column-break CSS for each freshly-loaded spine item.
            if (ReadiumReader.shouldInjectMOColumnBreakCssOnPageChange) {
                ReadiumReader.epubEvaluateJavascript("window.flutterReadium.injectMOBreakCSS()")
            }
        }
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        PluginLog.i(TAG, "::onExternalLinkActivated $url")
        emitOnExternalLinkActivated(url)
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        PluginLog.d(TAG, "::onVisualCurrentLocationChanged $locator")

        val currentKey = "${locator.href}@${locator.progression}@${locator.locations.position}"
        if (lastVisualLocationKey == currentKey) {
            return
        }

        lastVisualLocationKey = currentKey
        ReadiumReader.emitTextLocatorUpdate(locator)
        PluginLog.d(TAG, "::onVisualCurrentLocationChanged emitted text locator update")
    }

    override fun onVisualReaderIsReady() {
        PluginLog.i(TAG, "::onVisualReaderIsReady")
        if (!hasSentReady) {
            ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Ready)

            hasSentReady = true
        }
    }

    @Throws(IllegalArgumentException::class)
    private suspend fun setPreferencesFromMap(prefMap: Map<String, Any>) {
        PluginLog.d(TAG, "::setPreferencesFromMap")
        val newPreferences = FlutterEpubPreferences.fromMap(prefMap)
        updatePreferences(newPreferences)
        // Push the comic re-sync policy to the injected helper.
        newPreferences.syncPolicy?.let { policy ->
            ReadiumReader.epubEvaluateJavascript(
                "window.flutterReadium && window.flutterReadium.setComicSyncPolicy(${JSONObject.quote(policy)});",
            )
        }
    }

    private suspend fun emitOnPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        var emittingLocator = locator
        try {
            when {
                ReadiumReader.isPdf -> {
                    // Enrich PDF locator with the current TOC chapter title/href by
                    // matching "#page=N" fragments from the publication's table of contents.
                    emittingLocator = ReadiumReader.pdfEnrichLocatorWithTocHref(emittingLocator)
                }

                ReadiumReader.isComic -> {
                    // Comic (CBZ/DiViNa): no JS webview — just emit the locator as-is.
                    // ImageNavigatorFragment already produces a correct position-bearing locator.
                }

                else -> {
                    // EPUB: JS page-info eval + TOC href enrichment.
                    try {
                        evaluateJavascript("window.flutterReadium.getPageInformation()")
                            ?.let {
                                PageInformation.fromJson(
                                    it,
                                    locator.href,
                                )
                            }?.let { pageInfo ->
                                emittingLocator =
                                    emittingLocator.copyWithAdditionalLocations(pageInfo.otherLocations)
                            } ?: {
                            PluginLog.d(TAG, "::emitOnPageChanged - no page information")
                        }
                    } catch (e: Error) {
                        PluginLog.d(TAG, "::emitOnPageChanged - pageInformation error: $e")
                    }

                    emittingLocator = emittingLocator.addPageNumber(pageIndex, totalPages)
                    emittingLocator = ReadiumReader.epubEnrichLocatorWithTocHref(emittingLocator)
                }
            }

            channel.onPageChanged(emittingLocator)
            ReadiumReader.emitTextLocatorUpdate(emittingLocator)
            PluginLog.d(TAG, "::emitOnPageChanged: emitted $emittingLocator")
        } catch (e: Exception) {
            PluginLog.e(TAG, "::emitOnPageChanged: failed! $e")
        }
    }

    private fun emitOnExternalLinkActivated(url: AbsoluteUrl) {
        channel.onExternalLinkActivated(url)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        // TODO: To be safe we're doing everything on the Main thread right now.
        // Could probably optimize by using .IO and then change to Main
        // when affecting readerView or returning a result.
        launch {
            PluginLog.d(TAG, "::onMethodCall ${call.method}")
            when (call.method) {
                "setPreferences" -> {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val prefsMap =
                            call.arguments as? Map<String, Any> ?: run {
                                result.error(
                                    "FlutterReadium",
                                    "Failed to set preferences",
                                    "Invalid argument",
                                )
                                return@launch
                            }
                        when {
                            ReadiumReader.isPdf -> {
                                ReadiumReader.pdfUpdatePreferences(FlutterPdfPreferences.fromMap(prefsMap))
                            }

                            ReadiumReader.isComic -> {
                                // ImageNavigatorFragment has no user-configurable preferences.
                                PluginLog.d(TAG, "::setPreferences - not supported for comic")
                            }

                            else -> {
                                setPreferencesFromMap(prefsMap)
                            }
                        }
                        result.success(null)
                    } catch (ex: Exception) {
                        result.error("FlutterReadium", "Failed to set preferences", ex.message)
                    }
                }

                "go" -> {
                    val args = call.arguments as List<*>
                    val locatorJson = JSONObject(args[0] as String)
                    val animated = args[1] as Boolean
                    if (locatorJson.optString("type") == "") {
                        locatorJson.put("type", " ")
                        PluginLog.w(
                            TAG,
                            "Got locator with empty type! This shouldn't happen. $locatorJson",
                        )
                    }
                    val locator = Locator.fromJSON(locatorJson)!!
                    ReadiumReader.visualGoToLocator(locator, animated)
                    result.success(null)
                }

                "goBackward" -> {
                    val animated = call.arguments as Boolean
                    goBackward(animated)
                    result.success(null)
                }

                "goForward" -> {
                    val animated = call.arguments as Boolean
                    goForward(animated)
                    result.success(null)
                }

                "applyDecorations" -> {
                    if (ReadiumReader.isPdf || ReadiumReader.isComic) {
                        // PdfNavigatorFragment and ImageNavigatorFragment do not expose a
                        // DecorableNavigator surface in kotlin-toolkit 3.2.0.
                        PluginLog.d(TAG, "::applyDecorations - not supported for PDF/comic")
                        result.success(null)
                        return@launch
                    }
                    val args = call.arguments as List<*>
                    val groupId = args[0] as String

                    @Suppress("UNCHECKED_CAST")
                    val decorationListStr =
                        args[1] as List<String>
                    val decorations = decorationListStr.mapNotNull { decorationFromJson(it) }

                    ReadiumReader.applyDecorations(decorations, groupId)
                    result.success(null)
                }

                "configureSelectionActions" -> {
                    @Suppress("UNCHECKED_CAST")
                    val actions = call.arguments as? List<Map<String, String>> ?: emptyList()
                    ReadiumReader.selectionActions =
                        actions.map { map ->
                            SelectionActionConfig(
                                id = map["id"] ?: "",
                                title = map["title"] ?: "",
                            )
                        }
                    result.success(null)
                }

                "notifyUserNavigation" -> {
                    // User swiped or edge-tapped the reader (detected by the Flutter Listener
                    // above the platform view). Enter narration manual mode if narration is
                    // currently driving the reader; otherwise a no-op.
                    ReadiumReader.enterManualModeIfNarrating("notifyUserNavigation")
                    result.success(null)
                }

                "dispose" -> {
                    dispose()
                    result.success(null)
                }

                else -> {
                    PluginLog.w(TAG, "Unhandled call ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Navigate backward in the active visual navigator.
     */
    private suspend fun goBackward(animated: Boolean) {
        PluginLog.d(TAG, "::goBackward")
        ReadiumReader.visualGoBackward(animated)
    }

    private suspend fun goForward(animated: Boolean) {
        PluginLog.d(TAG, "::goForward")
        ReadiumReader.visualGoForward(animated)
    }

    private suspend fun evaluateJavascript(script: String): String? {
        val ret = ReadiumReader.epubEvaluateJavascript(script)
        if (ret == null || ret == "null" || ret == "undefined") {
            // Hopefully can't happen.
            PluginLog.w(TAG, "::evaluateJavascript($script) returned null $ret")

            return null
        }

        return ret
    }

    private suspend fun updatePreferences(preferences: FlutterEpubPreferences) {
        ReadiumReader.epubUpdatePreferences(preferences)
    }

    companion object {
        const val NAVIGATOR_FRAGMENT_TAG = "NAVIGATOR_READER_FRAGMENT"
    }
}
