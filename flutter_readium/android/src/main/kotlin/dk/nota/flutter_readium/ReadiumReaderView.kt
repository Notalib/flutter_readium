package dk.nota.flutter_readium

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.LinearLayout.generateViewId
import androidx.fragment.app.FragmentActivity
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.models.EpubReaderViewModel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.html.domRange
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "ReadiumReaderView"

internal const val textLocatorEventChannelName = "dk.nota.flutter_readium/text-locator"
internal const val viewTypeChannelName = "dk.nota.flutter_readium/ReadiumReaderWidget"

@OptIn(ExperimentalReadiumApi::class)
internal class ReadiumReaderView(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>,
    messenger: BinaryMessenger,
    attrs: AttributeSet? = null
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    EpubReaderFragment.Listener {

    private val channel: ReadiumReaderChannel
    private val readium = Readium(context)
    private val eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val layout: ViewGroup
    private val navigator: EpubReaderFragment

    private val activity
        get() = (context as ContextWrapper).baseContext as FragmentActivity
    private val fragmentManager
        get() = activity.supportFragmentManager

    /// Checks when the fragment starts and is safe to use.
    private val navigatorStarted get() = navigator.started
    private val currentLocator get() = navigator.currentLocator?.value

    private var userPreferences = EpubPreferences()
    private var initialLocations: Locator.Locations?

    val currentPublicationIdentifier: String

    override fun getView(): View {
        //Log.d(TAG, "::getView")
        return layout
    }

    override fun dispose() {
        Log.d(TAG, "::dispose")
        channel.setMethodCallHandler(null)

        navigator.listener = null
        navigator.let {
            fragmentManager.beginTransaction()
                .remove(it)
                .commitNow()
        }

        layout.removeAllViews()
        initialLocations = null
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
        val pubIdentifier = creationParams["pubIdentifier"] as String
        val publication = readium.publicationFromIdentifier(pubIdentifier)!!
        val pubUrl = readium.publicationUrlFromIdentifier(pubIdentifier)!!
        val locatorString = creationParams["initialLocator"] as String?
        val allowScreenReaderNavigation = creationParams["allowScreenReaderNavigation"] as Boolean?
        var initialLocator =
            if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)
        val initialPreferences =
            if (initPrefsMap == null) null else epubPreferencesFromMap(initPrefsMap, null)
        Log.d(TAG, "publication = $publication")
        currentPublicationIdentifier = pubIdentifier

        // Attempt to reuse existing fragment
        val epubReaderFragment =
            fragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as EpubReaderFragment?
        var reuseFragment = false
        if (epubReaderFragment != null) {
            Log.d(TAG, "existing fragment, can we reuse it?")
            val vm = epubReaderFragment.vm as? EpubReaderViewModel
            if (vm != null && vm.identifier == pubIdentifier && vm.pubUrl == pubUrl) {
                reuseFragment = true
                initialLocator = vm.locator ?: initialLocator
                epubReaderFragment.go(initialLocator!!, false)
            } else {
                // We can't reuse the fragment, remove it.
                reuseFragment = false

                fragmentManager.beginTransaction()
                    .remove(epubReaderFragment)
                    .commitNow()
            }
        }

        initialLocations = initialLocator?.locations?.let { if (canScroll(it)) it else null }

        if (!reuseFragment || epubReaderFragment == null) {
            val vm = EpubReaderViewModel();
            vm.identifier = pubIdentifier
            vm.pubUrl = pubUrl
            vm.publication = publication
            vm.locator = initialLocator
            vm.preferences = initialPreferences

            navigator = EpubReaderFragment()
            navigator.vm = vm

            layout = LinearLayout(context, attrs)
            layout.id = generateViewId()

            fragmentManager.beginTransaction()
                .add(layout, navigator, NAVIGATOR_FRAGMENT_TAG)
                .commitNow()
        } else {
            navigator = epubReaderFragment
            layout = epubReaderFragment.view?.rootView as FrameLayout
        }
        navigator.listener = this

        layout.setBackgroundColor(Color.TRANSPARENT)
        layout.setPadding(0, 0, 0, 0)

        // Set userPreferences to initialPreferences if provided.
        initialPreferences?.also { userPreferences = it }

        // By default reader contents are hidden from screen-readers, as not to trap them within it.
        // This can be toggled back on via the 'allowScreenReaderNavigation' creation param.
        // See issue: https://notalib.atlassian.net/browse/NOTA-9828
        if (allowScreenReaderNavigation != true) {
            layout.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        channel = ReadiumReaderChannel(messenger, "$viewTypeChannelName:$id")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(messenger, textLocatorEventChannelName)
        eventChannel.setStreamHandler(this)

        currentReadiumReaderView = this
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        val locations = initialLocations
        if (locations != null) {
            initialLocations = null
            CoroutineScope(Dispatchers.Main).launch {
                scrollToLocations(locations, toStart = true)
            }
        }
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression}"
        )

        CoroutineScope(Dispatchers.Main).launch { emitOnPageChanged(locator) }
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        Log.d(TAG, "::onExternalLinkActivated $url")
        CoroutineScope(Dispatchers.Main).launch { emitOnExternalLinkActivated(url) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    suspend fun getFirstVisibleLocator(): Locator? = navigator.firstVisibleElementLocator()

    @Throws(IllegalArgumentException::class)
    private suspend fun setPreferencesFromMap(prefMap: Map<String, String>) {
        Log.d(TAG, "::setPreferencesFromMap")
        val newPreferences = epubPreferencesFromMap(prefMap, null)
            ?: throw IllegalArgumentException("failed to deserialize map into EpubPreferences")
        this.userPreferences = newPreferences
        setPreferences(newPreferences)
    }

    private suspend fun emitOnPageChanged(locator: Locator) {
        try {
            val locatorWithFragments = getLocatorFragments(locator)
            if (locatorWithFragments == null) {
                Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed!")
                return
            }

            channel.onPageChanged(locatorWithFragments)
            eventSink?.success(jsonEncode(locatorWithFragments.toJSON()))
        } catch (e: Exception) {
            Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed! $e")
        }
    }

    private fun emitOnExternalLinkActivated(url: AbsoluteUrl) {
        channel.onExternalLinkActivated(url)
    }

    private suspend fun getLocatorFragments(locator: Locator): Locator? {
        val json =
            evaluateJavascript("window.epubPage.getLocatorFragments(${locator.toJSON()}, $isVerticalScroll)")
        try {
            if (json == null || json == "null" || json == "undefined") {
                Log.e(TAG, "getLocatorFragments: window.epubPage.getVisibleRange failed!")
                return null
            }
            val jsonLocator = jsonDecode(json) as JSONObject
            val locatorWithFragments = Locator.fromJSON(jsonLocator)

            return locatorWithFragments
        } catch (e: Exception) {
            Log.e(
                TAG,
                "getLocatorFragments: window.epubPage.getVisibleRange json: $json failed! $e"
            )
        }
        return null
    }

    private val isVerticalScroll: Boolean
        get() {
            return userPreferences.scroll ?: false
        }

    private suspend fun scrollToLocations(
        locations: Locator.Locations,
        toStart: Boolean
    ) {
        val json = locations.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json, toStart: $toStart")
        evaluateJavascript("window.epubPage.scrollToLocations($json,$isVerticalScroll,$toStart);")
    }

    fun justGoToLocator(locator: Locator, animated: Boolean) {
        Log.d(TAG, "::justGoToLocator: Go to ${locator.href} from ${currentLocator?.href}")
        go(locator, animated)
    }

    private suspend fun goToLocator(locator: Locator, animated: Boolean) {
        val locations = locator.locations
        val shouldScroll = canScroll(locations)
        val shouldGo = currentLocator?.href?.isEquivalent(locator.href) == false

        if (shouldGo) {
            Log.d(TAG, "::goToLocator: Go to ${locator.href} from ${currentLocator?.href}")
            go(locator, animated)
        } else if (!shouldScroll) {
            Log.w(TAG, "::goToLocator: Already at ${locator.href}, no scroll target, go to start")
            scrollToLocations(Locator.Locations(progression = 0.0), true)
        } else {
            Log.d(TAG, "::goToLocator: Don't go to ${locator.href}, already there")
        }
        if (shouldScroll) {
            scrollToLocations(locations, false)
        }
    }

    private suspend fun setLocation(
        locator: Locator,
        isAudioBookWithText: Boolean
    ) {
        val json = locator.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json")
        evaluateJavascript("window.epubPage.setLocation($json, $isAudioBookWithText);")
    }

    fun applyDecorations(
        decorations: List<Decoration>,
        group: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            navigator.applyDecorations(decorations, group)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // TODO: To be safe we're doing everything on the Main thread right now.
        // Could probably optimize by using .IO and then change to Main
        // when affecting readerView or returning a result.
        CoroutineScope(Dispatchers.Main).launch {
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
                    goToLocator(locator, animated)
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
                    var visible = locator.href == navigator.currentLocator?.value?.href
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
                    val jsonRes = evaluateJavascript("window.epubPage.isReaderReady();") ?: "false"
                    try {
                        val isReady = jsonDecode(jsonRes) as Boolean
                        result.success(isReady)
                    } catch (e: Error) {
                        Log.e(TAG, "::isReaderReady - invalid response \"jsonRes\" - $e")
                        result.success(false)
                    }
                }

                "getLocatorFragments" -> {
                    val args = call.arguments as String?
                    Log.d(TAG, "::====== $args")
                    val locatorJson = JSONObject(args!!)
                    Log.d(TAG, "::====== $locatorJson")

                    val locator = getLocatorFragments(Locator.fromJSON(locatorJson)!!)
                    Log.d(TAG, "::====== $locator")

                    result.success(jsonEncode(locator?.toJSON()))
                }

                "applyDecorations" -> {
                    val args = call.arguments as List<*>
                    val groupId = args[0] as String
                    @Suppress("UNCHECKED_CAST")
                    val decorationListStr = args[1] as List<Map<String, String>>
                    val decorations = decorationListStr.mapNotNull { decorationFromMap(it) }

                    applyDecorations(decorations, groupId)
                    result.success(null)
                }

                "dispose" -> {
                    layout.removeAllViews()
                    fragmentManager.beginTransaction()
                        .remove(navigator)
                        .commitNow()
                    currentReadiumReaderView = null
                    initialLocations = null
                    eventSink = null
                    eventChannel.setStreamHandler(null)
                    channel.setMethodCallHandler(null)
                    result.success(null)
                }

                else -> {
                    Log.e(TAG, "Unhandled call ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    private fun go(locator: Locator, animated: Boolean) {
        Log.d(TAG, "::go ${locator.href}")
        CoroutineScope(Dispatchers.Main).launch {
            navigator.apply {
                afterFragmentStarted()
                if (go(locator, animated)) {
                    Log.d(TAG, "GO returned.")
                } else {
                    Log.w(TAG, "GO FAILED!")
                }
            }
        }
    }

    private suspend fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        afterFragmentStarted()
        navigator.goLeft(animated)
    }

    private suspend fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        afterFragmentStarted()
        navigator.goRight(animated)
    }

    private suspend fun evaluateJavascript(script: String): String? {
        // Make sure fragment has started, otherwise fragment.evaluateJavascript may fail early and
        // return null.
        afterFragmentStarted()

        val ret = navigator.evaluateJavascript(script)
        if (ret == null || ret == "null" || ret == "undefined") {
            // Hopefully can't happen.
            Log.e(TAG, "::evaluateJavascript($script) returned null $ret")

            return null
        }
        return ret
    }

    private suspend fun setPreferences(preferences: EpubPreferences) {
        navigator.setPreferences(preferences)
    }

    private suspend fun afterFragmentStarted() {
        if (!navigatorStarted.value) {
            navigatorStarted.first { it }
            Log.d(TAG, "::afterFragmentStarted: Resuming call")
        }
    }

    companion object {
        const val NAVIGATOR_FRAGMENT_TAG = "NAVIGATOR_READER_FRAGMENT"
    }
}

private fun canScroll(locations: Locator.Locations) =
    locations.domRange != null || locations.cssSelector != null || locations.progression != null
