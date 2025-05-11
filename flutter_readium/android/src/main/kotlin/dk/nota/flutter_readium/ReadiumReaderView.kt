package dk.nota.flutter_readium

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.VisualNavigator
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.html.domRange

private const val TAG = "ReadiumReaderView"

internal const val textLocatorChannelName = "dk.nota.flutter_readium/text-locator"
internal const val viewType = "dk.nota.flutter_readium/ReadiumReaderWidget"

internal class ReadiumReaderView(
  context: Context,
  id: Int,
  creationParams: Map<String?, Any?>,
  messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler, EpubNavigatorView.Listener {
  private val channel: ReadiumReaderChannel
  private val readiumView: EpubNavigatorView

  private var userPreferences: Map<String, String> = mapOf()
  private var initialLocations: Locator.Locations?

  // Create a CoroutineScope using the Main (UI) dispatcher
  // TODO: What was/is this used for?
  private var scope = CoroutineScope(Dispatchers.Main)

  override fun getView(): View {
    //Log.d(TAG, "::getView")
    return readiumView
  }

  override fun dispose() {
    Log.d(TAG, "::dispose")
    channel.setMethodCallHandler(null)

    readiumView.removeAllViews()
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
    val publication = publicationFromIdentifier(pubIdentifier)!!
    val locatorString = creationParams["initialLocator"] as String?
    val initialLocator =
      if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)
    val initialPreferences =
      if (initPrefsMap == null) null else EpubPreferencesFromMap(initPrefsMap, null)
    Log.d(TAG, "publication = $publication")

    initialLocations = initialLocator?.locations?.let { if (canScroll(it)) it else null }
    readiumView = EpubNavigatorView(context, publication, initialLocator, initialPreferences, this)

    // TODO: This should be optional as passed as parameter to the view.
    // Not sure if this will solve this issue: https://notalib.atlassian.net/browse/NOTA-9828
    readiumView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS

    channel = ReadiumReaderChannel(messenger, "$viewType:$id")
    channel.setMethodCallHandler(this)

    currentReadiumReaderView = this
  }

  override fun onPageLoaded() {
    val locations = initialLocations
    if (locations != null) {
      initialLocations = null
      CoroutineScope(Dispatchers.Main).launch {
        scrollToLocations(locations, toStart = true)
      }
    }
  }

  override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
    CoroutineScope(Dispatchers.Main).launch { emitOnPageChanged(locator) }
  }

  suspend fun getFirstVisibleLocator(): Locator? = this.readiumView.getFirstVisibleLocator()

  private fun setPreferencesFromMap(prefMap: Map<String, String>) {
    Log.d(TAG, "::setPreferencesFromMap")
    this.userPreferences = prefMap
    CoroutineScope(Dispatchers.Main).launch {
      readiumView.setPreferencesFromMap(prefMap)
      readiumView.setBackgroundColor(Color.TRANSPARENT)
      readiumView.setPadding(0, 0, 0, 0)
    }
  }

  private suspend fun emitOnPageChanged(locator: Locator) {
    try {
      val locatorWithFragments = getLocatorFragments(locator);
      if (locatorWithFragments == null) {
        Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed!")
        return
      }

      channel.onPageChanged(locatorWithFragments)
    }
    catch(e: Exception) {
      Log.e(TAG, "emitOnPageChanged: window.epubPage.getVisibleRange failed! $e")
    }
  }

  private suspend fun getLocatorFragments(locator: Locator) : Locator? {
    val json = readiumView.evaluateJavascript("window.epubPage.getLocatorFragments(${locator.toJSON()}, $isVerticalScroll)")
    try {
      if (json == null || json == "null" || json == "undefined") {
        Log.e(TAG, "getLocatorFragments: window.epubPage.getVisibleRange failed!")
        return null
      }
      val jsonLocator = jsonDecode(json) as JSONObject;
      val locatorWithFragments = Locator.fromJSON(jsonLocator);

      return locatorWithFragments
    }
    catch(e: Exception) {
      Log.e(TAG, "getLocatorFragments: window.epubPage.getVisibleRange json: $json failed! $e")
    }
    return null
  }

  private val isVerticalScroll: Boolean get() {
    // TODO: Use current preferences
    return userPreferences?.get("--USER__scroll") == "readium-scroll-on"
  }

  private suspend fun scrollToLocations(
    locations: Locator.Locations,
    toStart: Boolean
  ) {
    val json = locations.toJSON().toString()
    Log.d(TAG, "::scrollToLocations: Go to locations $json, toStart: $toStart")
    readiumView.evaluateJavascript("window.epubPage.scrollToLocations($json,$isVerticalScroll,$toStart)")
  }

  suspend fun justGoToLocator(locator: Locator, animated: Boolean) {
    Log.d(TAG, "::goToLocator: Go to ${locator.href} from ${readiumView.currentLocator.href}")
    return readiumView.go(locator, animated)
  }

  suspend fun goToLocator(locator: Locator, animated: Boolean) {
    val locations = locator.locations
    val shouldScroll = canScroll(locations)
    val shouldGo = readiumView.currentLocator.href != locator.href

    if (shouldGo) {
      Log.d(TAG, "::goToLocator: Go to ${locator.href} from ${readiumView.currentLocator.href}")
      readiumView.go(locator, animated)
    } else if (!shouldScroll) {
      Log.d(TAG, "::goToLocator: Already at ${locator.href}, no scroll target, go to start")
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
    readiumView.evaluateJavascript("window.epubPage.setLocation($json, $isAudioBookWithText);")
  }

  suspend fun applyDecorations(
    decorations: List<Decoration>,
    group: String,
    ) {
    CoroutineScope(Dispatchers.Main).launch {
      readiumView.applyDecorations(decorations, group)
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    CoroutineScope(Dispatchers.Main).launch {
      //Log.d(TAG, "::onMethodCall ${call.method}")
      when (call.method) {
        "setPreferences" -> {
          @Suppress("UNCHECKED_CAST")
          val prefsMap = call.arguments as Map<String, String>
          setPreferencesFromMap(prefsMap)
          result.success(null)
        }
        "go" -> {
          val args = call.arguments as List<*>
          val locatorJson = JSONObject(args[0] as String)
          val animated = args[1] as Boolean
          val isAudioBookWithText = args[2] as Boolean
          if (locatorJson.optString("type") == "") {
            locatorJson.put("type", " ")
            Log.e(TAG, "Got locator with empty type! This shouldn't happen. $locatorJson")
          }
          val locator = Locator.fromJSON(locatorJson)!!
          goToLocator(locator, animated)
          setLocation(locator, isAudioBookWithText)
          result.success(null)
        }
        "goLeft" -> {
          val animated = call.arguments as Boolean
          readiumView.goLeft(animated)
          result.success(null)
        }
        "goRight" -> {
          val animated = call.arguments as Boolean
          readiumView.goRight(animated)
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
          val visible = locator.href == readiumView.currentLocator.href && jsonDecode(
            readiumView.evaluateJavascript("window.epubPage.isLocatorVisible($args);") ?: "false"
          ) as Boolean
          result.success(visible)
        }
        "isReaderReady" -> {
          val isReady = jsonDecode(
            readiumView.evaluateJavascript("window.epubPage.isReaderReady();") ?: "false"
          ) as Boolean
          result.success(isReady)
        }
        "getLocatorFragments" -> {
          val args = call.arguments as String?
          Log.d(TAG, "::====== $args")
           val locatorJson = JSONObject(args)
          Log.d(TAG, "::====== $locatorJson")

          val locator = getLocatorFragments(Locator.fromJSON(locatorJson)!!)
          Log.d(TAG, "::====== $locator")

          result.success(jsonEncode(locator?.toJSON()))
        }
        "dispose" -> {
          readiumView.removeAllViews()
          initialLocations = null
          result.success(null)
        }
        else -> {
          Log.e(TAG, "Unhandled call ${call.method}")
          result.notImplemented()
        }
      }
      //Log.d(TAG, "::onMethodCall exit ${call.method}")
    }
  }
}

private fun jsonDecode(json: String): Any = JSONArray("[$json]")[0]

private fun jsonEncode(json: Any?): String = when (json) {
  is JSONArray -> json.toString()
  is JSONObject -> json.toString()
  is Nothing? -> "null"
  else -> {
    val ret = JSONArray(listOf(json)).toString()
    ret.substring(1, ret.length - 1)
  }
}

private const val isLoading = 1
private const val isScrolling = 2

private fun canScroll(locations: Locator.Locations) =
  locations.domRange != null || locations.cssSelector != null || locations.progression != null
