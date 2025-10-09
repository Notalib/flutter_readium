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
import dk.nota.flutter_readium.events.TextLocatorEventChannel
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.navigators.EpubNavigator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "ReadiumReaderView"
internal const val viewTypeChannelName = "dk.nota.flutter_readium/ReadiumReaderWidget"

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class ReadiumReaderWidget(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>,
    messenger: BinaryMessenger,
    attrs: AttributeSet? = null
) : PlatformView, MethodChannel.MethodCallHandler,
    EpubReaderFragment.Listener, EpubNavigator.VisualListener {

    private val channel: ReadiumReaderChannel
    private var textLocatorEventChannel: TextLocatorEventChannel? = null
    private val layout: ViewGroup

    private val activity
        get() = (context as ContextWrapper).baseContext as FragmentActivity
    private val fragmentManager
        get() = activity.supportFragmentManager

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun getView(): View {
        //Log.d(TAG, "::getView")
        return layout
    }

    override fun dispose() {
        Log.d(TAG, "::dispose")
        ReadiumReader.epubClose()
        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = null
        channel.setMethodCallHandler(null)

        mainScope.coroutineContext.cancelChildren()
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
        val initPrefsMap = creationParams["preferences"] as Map<String, String>?
        val publication = ReadiumReader.currentPublication
        val locatorString = creationParams["initialLocator"] as String?
        val allowScreenReaderNavigation = creationParams["allowScreenReaderNavigation"] as Boolean?
        var initialLocator =
            if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)
        val initialPreferences =
            if (initPrefsMap == null) EpubPreferences() else epubPreferencesFromMap(
                initPrefsMap,
                null
            )
        Log.d(TAG, "publication = $publication")

        layout = LinearLayout(context, attrs)
        layout.id = generateViewId()
        layout.setBackgroundColor(Color.TRANSPARENT)
        layout.setPadding(0, 0, 0, 0)

        ReadiumReader.currentReaderWidget = this

        channel = ReadiumReaderChannel(messenger, "$viewTypeChannelName:$id")
        channel.setMethodCallHandler(this)

        textLocatorEventChannel = TextLocatorEventChannel(messenger)

        // By default reader contents are hidden from screen-readers, as not to trap them within it.
        // This can be toggled back on via the 'allowScreenReaderNavigation' creation param.
        // See issue: https://notalib.atlassian.net/browse/NOTA-9828
        if (allowScreenReaderNavigation != true) {
            layout.importantForAccessibility =
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        // Remove existing fragment if any (this is to avoid crashing on restore).
        (fragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as? EpubReaderFragment)?.let { fragment ->
            Log.d(TAG, "::init - remove existing fragment")

            fragmentManager.commitNow {
                remove(fragment)
            }
        }

        mainScope.launch {
            ReadiumReader.epubEnable(
                initialLocator,
                initialPreferences,
                messenger,
                fragmentManager,
                layout,
                this@ReadiumReaderWidget,
            )
        }
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
    }

    // To avoid duplicate onPageChanged events.
    private var lastPageLoadedKey: String? = null

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        val currentKey = "${locator.href}@${locator.locations.progression}"
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression} ${locator.locations}"
        )


        if (lastPageLoadedKey == currentKey) {
            // Sometimes we get duplicate calls to onPageChanged with same locator.
            // Not sure why, but ignore them.
            return
        }

        // TODO: Should we do something with the pageIndex and totalPages?
        lastPageLoadedKey = currentKey

        mainScope.launch { emitOnPageChanged(locator) }
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        Log.d(TAG, "::onExternalLinkActivated $url")
        mainScope.launch { emitOnExternalLinkActivated(url) }
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        Log.d(TAG, "::onVisualCurrentLocationChanged $Locator")
    }

    override fun onVisualReaderIsReady() {
        Log.d(TAG, "::onVisualReaderIsReady")
    }

    suspend fun getFirstVisibleLocator(): Locator? = withScope(mainScope) { ReadiumReader.getFirstVisibleLocator() }

    @Throws(IllegalArgumentException::class)
    private fun setPreferencesFromMap(prefMap: Map<String, String>) {
        Log.d(TAG, "::setPreferencesFromMap")
        val newPreferences = epubPreferencesFromMap(prefMap, null)
        updatePreferences(newPreferences)
    }

    private suspend fun emitOnPageChanged(locator: Locator) {
        try {
            val locatorWithFragments = ReadiumReader.getEpubLocatorFragments(locator)
            if (locatorWithFragments == null) {
                Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed!")
                return
            }

            channel.onPageChanged(locatorWithFragments)
            textLocatorEventChannel?.sendEvent(locatorWithFragments)
        } catch (e: Exception) {
            Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed! $e")
        }
    }

    private fun emitOnExternalLinkActivated(url: AbsoluteUrl) {
        channel.onExternalLinkActivated(url)
    }

    private suspend fun setLocation(
        locator: Locator,
        isAudioBookWithText: Boolean
    ) {
        val json = locator.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json")
        evaluateJavascript("window.epubPage.setLocation($json, $isAudioBookWithText);")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // TODO: To be safe we're doing everything on the Main thread right now.
        // Could probably optimize by using .IO and then change to Main
        // when affecting readerView or returning a result.
        mainScope.launch {
            Log.d(TAG, "::onMethodCall ${call.method}")
            when (call.method) {
                "setPreferences" -> {
                    @Suppress("UNCHECKED_CAST")
                    val prefsMap = call.arguments as Map<String, String>
                    try {
                        setPreferencesFromMap(prefsMap)
                        result.success(null)
                    } catch (ex: Exception) {
                        result.error("FlutterReadium", "Failed to set preferences", ex.message)
                    }
                }

                "go" -> {
                    val args = call.arguments as List<*>
                    val locatorJson = JSONObject(args[0] as String)
                    val animated = args[1] as Boolean
                    val isAudioBookWithText = args[2] as Boolean
                    if (locatorJson.optString("type") == "") {
                        locatorJson.put("type", " ")
                        Log.e(
                            TAG,
                            "Got locator with empty type! This shouldn't happen. $locatorJson"
                        )
                    }
                    val locator = Locator.fromJSON(locatorJson)!!
                    ReadiumReader.epubGoToLocator(locator, animated)
                    setLocation(locator, isAudioBookWithText)
                    result.success(null)
                }

                "goLeft" -> {
                    val animated = call.arguments as Boolean
                    goLeft(animated)
                    result.success(null)
                }

                "goRight" -> {
                    val animated = call.arguments as Boolean
                    goRight(animated)
                    result.success(null)
                }

                "setLocation" -> {
                    val args = call.arguments as List<*>
                    val locatorJson = JSONObject(args[0] as String)
                    val isAudioBookWithText = args[1] as Boolean
                    val locator = Locator.fromJSON(locatorJson)!!
                    setLocation(locator, isAudioBookWithText)
                    result.success(null)
                }

                "isLocatorVisible" -> {
                    val args = call.arguments as String
                    val locatorJson = JSONObject(args)
                    val locator = Locator.fromJSON(locatorJson)!!
                    var visible = locator.href == ReadiumReader.epubCurrentLocator?.href
                    if (visible) {
                        val jsonRes =
                            evaluateJavascript("window.epubPage.isLocatorVisible($args);")
                                ?: "false"
                        try {
                            visible = jsonDecode(jsonRes) as Boolean
                        } catch (e: Error) {
                            Log.e(TAG, "::isLocatorVisible - invalid response:$jsonRes - e:$e")
                            visible = false
                        }
                    }
                    result.success(visible)
                }

                "isReaderReady" -> {
                    try {
                        result.success(ReadiumReader.epubIsReaderReady())
                    } catch (e: Error) {
                        Log.e(TAG, "::isReaderReady - error getting state - $e")
                        result.success(false)
                    }
                }

                "getLocatorFragments" -> {
                    val args = call.arguments as String?
                    Log.d(TAG, "::====== $args")
                    val locatorJson = JSONObject(args!!)
                    Log.d(TAG, "::====== $locatorJson")

                    val locator =
                        ReadiumReader.epubGetLocatorFragments(Locator.fromJSON(locatorJson)!!)
                    Log.d(TAG, "::====== $locator")

                    result.success(jsonEncode(locator?.toJSON()))
                }

                "applyDecorations" -> {
                    val args = call.arguments as List<*>
                    val groupId = args[0] as String

                    @Suppress("UNCHECKED_CAST")
                    val decorationListStr = args[1] as List<Map<String, String>>
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

    fun go(locator: Locator, animated: Boolean) {
        Log.d(TAG, "::go ${locator.href}")
        mainScope.launch {
            ReadiumReader.epubGoToLocator(locator, animated)
        }
    }

    private fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        ReadiumReader.epubGoLeft(animated)
    }

    private fun goRight(animated: Boolean) {
        ReadiumReader.epubGoRight(animated)
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

    private fun updatePreferences(preferences: EpubPreferences) {
        ReadiumReader.epubUpdatePreferences(preferences)
    }

    companion object {
        const val NAVIGATOR_FRAGMENT_TAG = "NAVIGATOR_READER_FRAGMENT"
    }
}
