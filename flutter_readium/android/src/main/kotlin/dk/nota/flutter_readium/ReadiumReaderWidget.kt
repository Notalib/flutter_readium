package dk.nota.flutter_readium

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.LinearLayout.generateViewId
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.commitNow
import dk.nota.flutter_readium.events.ReadiumError
import dk.nota.flutter_readium.events.ReadiumReaderStatus
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.fragments.PdfReaderFragment
import dk.nota.flutter_readium.models.PageInformation
import dk.nota.flutter_readium.navigators.EpubNavigator
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
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.mediatype.MediaType

private const val TAG = "ReadiumReaderView"
internal const val viewTypeChannelName = "dk.nota.flutter_readium/ReadiumReaderWidget"

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
    private val channel: ReadiumReaderChannel

    /**
     * Make sure we only sent ready status once.
     */
    var hasSentReady = false

    /**
     * Whether the current publication is a PDF — drives whether init wires the
     * `pdfEnable` / `pdfGo*` path or the `epubEnable` / `epubGo*` path.
     * Decided once at construction; we never hot-swap content type.
     */
    private val isPdf: Boolean

    private val layout: ViewGroup

    private val activity
        get() = (context as ContextWrapper).baseContext as FragmentActivity
    private val fragmentManager
        get() = activity.supportFragmentManager

    override fun getView(): View {
        // Log.d(TAG, "::getView")
        return layout
    }

    override fun dispose() {
        Log.d(TAG, "::dispose")
        if (isPdf) {
            ReadiumReader.pdfClose()
        } else {
            ReadiumReader.epubClose()
        }

        ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Closed)
        hasSentReady = false

        channel.setMethodCallHandler(null)

        coroutineContext.cancelChildren()
        layout.removeAllViews()
    }

    override fun onFlutterViewAttached(flutterView: View) {
        // Seems to never be called, so can't use this. Flutter bug?
        Log.d(TAG, "::onFlutterViewAttached")
        super.onFlutterViewAttached(flutterView)
    }

    override fun onFlutterViewDetached() {
        // Seems to never be called, so can't use this. Flutter bug?
        Log.d(TAG, "::onFlutterViewDetached")
        super.onFlutterViewDetached()
    }

    init {
        Log.d(TAG, "::init")

        @Suppress("UNCHECKED_CAST")
        val initPrefsMap =
            creationParams["preferences"] as Map<String, String>?
        val publication = ReadiumReader.currentPublication
        val locatorString = creationParams["initialLocator"] as String?
        val allowScreenReaderNavigation = creationParams["allowScreenReaderNavigation"] as Boolean?
        val initialLocator =
            if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)

        isPdf =
            publication?.conformsTo(Publication.Profile.PDF) == true ||
                publication?.readingOrder?.firstOrNull()?.mediaType?.matches(MediaType.PDF) == true

        // EPUB preferences are only relevant when we'll wire the EPUB navigator —
        // for PDFs we ignore the incoming preferences map for now (Phase 5 will
        // introduce a proper PDF preferences model).
        val initialPreferences =
            if (isPdf) {
                FlutterEpubPreferences()
            } else {
                initPrefsMap?.let { FlutterEpubPreferences.fromMap(it) } ?: FlutterEpubPreferences()
            }

        Log.d(TAG, "publication = $publication (isPdf=$isPdf)")

        layout = LinearLayout(context, attrs)
        layout.id = generateViewId()
        layout.setBackgroundColor(Color.TRANSPARENT)
        layout.setPadding(0, 0, 0, 0)

        ReadiumReader.currentReaderWidget = this

        channel = ReadiumReaderChannel(messenger, "$viewTypeChannelName:$id")
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
            Log.d(TAG, "::init - remove existing fragment")
            fragmentManager.commitNow {
                remove(fragment)
            }
        }

        launch {
            try {
                if (isPdf) {
                    ReadiumReader.pdfEnable(
                        initialLocator,
                        fragmentManager,
                        layout,
                        this@ReadiumReaderWidget,
                    )
                } else {
                    ReadiumReader.epubEnable(
                        initialLocator,
                        initialPreferences,
                        fragmentManager,
                        layout,
                        this@ReadiumReaderWidget,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "::init - enable failed (isPdf=$isPdf)", e)
                ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Error)
                ReadiumReader.emitError(ReadiumError(e))
            }
        }
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
    }

    // To avoid duplicate onPageChanged events.
    private var lastPageLoadedKey: String? = null

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        val currentKey = "${locator.href}@${locator.progression}"
        Log.d(
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
        }
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        Log.d(TAG, "::onExternalLinkActivated $url")
        emitOnExternalLinkActivated(url)
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        Log.d(TAG, "::onVisualCurrentLocationChanged $locator")
    }

    override fun onVisualReaderIsReady() {
        Log.d(TAG, "::onVisualReaderIsReady")
        if (!hasSentReady) {
            ReadiumReader.emitReaderStatusUpdate(ReadiumReaderStatus.Ready)

            hasSentReady = true
        }
    }

    @Throws(IllegalArgumentException::class)
    private suspend fun setPreferencesFromMap(prefMap: Map<String, Any>) {
        Log.d(TAG, "::setPreferencesFromMap")
        val newPreferences = FlutterEpubPreferences.fromMap(prefMap)
        updatePreferences(newPreferences)
    }

    private suspend fun emitOnPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        var emittingLocator = locator

            if (isPdf) {
                // Enrich PDF locator with the current TOC chapter title/href by
                // matching "#page=N" fragments from the publication's table of contents.
                emittingLocator = ReadiumReader.pdfEnrichLocatorWithTocHref(emittingLocator)
            } else {
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
                        Log.d(TAG, "::emitOnPageChanged - no page information")
                    }
                } catch (e: Error) {
                    Log.d(TAG, "::emitOnPageChanged - pageInformation error: $e")
                }

                emittingLocator = emittingLocator.addPageNumber(pageIndex, totalPages)
                emittingLocator = ReadiumReader.epubEnrichLocatorWithTocHref(emittingLocator)
            }

            channel.onPageChanged(emittingLocator)
            ReadiumReader.emitTextLocatorUpdate(emittingLocator)
            Log.d(TAG, "emitOnPageChanged: emitted $emittingLocator")
        } catch (e: Exception) {
            Log.e(TAG, "emitOnPageChanged: failed! $e")
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
            Log.d(TAG, "::onMethodCall ${call.method}")
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
                        if (isPdf) {
                            ReadiumReader.pdfUpdatePreferences(FlutterPdfPreferences.fromMap(prefsMap))
                        } else {
                            setPreferencesFromMap(prefsMap)
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
                        Log.e(
                            TAG,
                            "Got locator with empty type! This shouldn't happen. $locatorJson",
                        )
                    }
                    val locator = Locator.fromJSON(locatorJson)!!
                    if (isPdf) {
                        ReadiumReader.pdfGoToLocator(locator, animated)
                    } else {
                        ReadiumReader.epubGoToLocator(locator, animated)
                    }
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
                    if (isPdf) {
                        // Pdfium-backed PdfNavigatorFragment does not expose a
                        // DecorableNavigator surface in kotlin-toolkit 3.1.2.
                        Log.d(TAG, "::applyDecorations - not supported for PDF")
                        result.success(null)
                        return@launch
                    }
                    val args = call.arguments as List<*>
                    val groupId = args[0] as String

                    @Suppress("UNCHECKED_CAST")
                    val decorationListStr =
                        args[1] as List<Map<String, String>>
                    val decorations = decorationListStr.mapNotNull { decorationFromMap(it) }

                    ReadiumReader.applyDecorations(decorations, groupId)
                    result.success(null)
                }

                "dispose" -> {
                    dispose()
                    result.success(null)
                }

                else -> {
                    Log.e(TAG, "Unhandled call ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Navigate backward — dispatches to PDF or EPUB based on the current
     * publication type.
     */
    private suspend fun goBackward(animated: Boolean) {
        Log.d(TAG, "::goBackward (isPdf=$isPdf)")
        if (isPdf) {
            ReadiumReader.pdfGoBackward(animated)
        } else {
            ReadiumReader.epubGoBackward(animated)
        }
    }

    private suspend fun goForward(animated: Boolean) {
        Log.d(TAG, "::goForward (isPdf=$isPdf)")
        if (isPdf) {
            ReadiumReader.pdfGoForward(animated)
        } else {
            ReadiumReader.epubGoForward(animated)
        }
    }

    private suspend fun evaluateJavascript(script: String): String? {
        val ret = ReadiumReader.epubEvaluateJavascript(script)
        if (ret == null || ret == "null" || ret == "undefined") {
            // Hopefully can't happen.
            Log.e(TAG, "::evaluateJavascript($script) returned null $ret")

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
