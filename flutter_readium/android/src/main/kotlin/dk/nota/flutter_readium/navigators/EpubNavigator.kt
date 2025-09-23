package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dk.nota.flutter_readium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dk.nota.flutter_readium.canScroll
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.jsonDecode
import dk.nota.flutter_readium.models.EpubReaderViewModel
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.collections.set
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "EpubNavigator"
private const val currentVisualCurrentLocatorKey = "currentVisualCurrentLocator"
private const val epubPreferencesKey = "epubPreferences"

@OptIn(ExperimentalReadiumApi::class)
class EpubNavigator : Navigator, EpubReaderFragment.Listener {
    private val initialPreferences: EpubPreferences

    constructor(
        publication: Publication,
        initialLocator: Locator?,
        visualListener: VisualListener,
        initialPreferences: EpubPreferences = EpubPreferences()
    ) : super(publication, initialLocator) {
        this.initialPreferences = initialPreferences
        this.visualListener = visualListener

        this.state[currentVisualCurrentLocatorKey] = initialLocator
        this.state[epubPreferencesKey] = initialPreferences
    }

    interface VisualListener {
        fun onPageLoaded()

        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        fun onExternalLinkActivated(url: AbsoluteUrl)

        fun onVisualCurrentLocationChanged(locator: Locator)

        fun onVisualReaderIsReady()
    }

    val visualListener: VisualListener

    private var epubNavigator: EpubReaderFragment? = null
    var editor: EpubPreferencesEditor? = null

    var initialLocations: Locator.Locations? = null

    val preferences: EpubPreferences?
        get() = editor?.preferences

    val currentLocator
        get() = epubNavigator?.currentLocator

    /// Checks when the fragment starts and is safe to use.
    private val navigatorStarted
        get() = epubNavigator!!.started

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    private val isVerticalScroll: Boolean
        get() {
            return editor?.preferences?.scroll ?: false
        }

    override suspend fun initNavigator() {
        initialLocations = initialLocator?.locations?.let { if (canScroll(it)) it else null }

        epubNavigator = EpubReaderFragment().apply {
            vm = EpubReaderViewModel().apply {
                navigatorFactory = EpubNavigatorFactory(publication)
                locator = this@EpubNavigator.initialLocator
                preferences = this@EpubNavigator.initialPreferences

                editor =
                    navigatorFactory!!.createPreferencesEditor(initialPreferences)
            }
            listener = this@EpubNavigator
        }
    }

    fun attachNavigator(fragmentManager: FragmentManager, viewGroup: ViewGroup) {
        val navigator = epubNavigator ?: return
        fragmentManager.commitNow {
            add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
        }
    }

    fun go(locator: Locator, animated: Boolean) {
        epubNavigator?.apply {
            mainScope.launch {
                afterFragmentStarted()
                if (go(locator, animated)) {
                    Log.d(TAG, "GO returned.")
                } else {
                    Log.w(TAG, "GO FAILED!")
                }
            }
        }
    }

    fun updatePreferences(epubPrefs: EpubPreferences) {
        Log.d(TAG, "::setPreferences")
        if (editor == null) {
            return
        }

        try {
            editor?.apply {
                fontFamily.set(epubPrefs.fontFamily)
                fontSize.set(epubPrefs.fontSize)
                fontWeight.set(epubPrefs.fontWeight)
                scroll.set(epubPrefs.scroll)
                backgroundColor.set(epubPrefs.backgroundColor)
                textColor.set(epubPrefs.textColor)

                epubNavigator?.updatePreferences(preferences)
                state[epubPreferencesKey] = preferences
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = epubNavigator ?: return

        navigator.currentLocator!!
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach {
                onCurrentLocatorChanges(it)
                state[currentVisualCurrentLocatorKey] = it
            }
            .launchIn(CoroutineScope(Dispatchers.Main))
            .let { jobs.add(it) }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentVisualCurrentLocatorKey,
                (state[currentVisualCurrentLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            preferences?.let { prefs ->
                putString(
                    epubPreferencesKey,
                    Json.encodeToString(EpubPreferences.serializer(), prefs)
                )
            }
        }
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        visualListener.onPageLoaded()

        mainScope.launch {
            val locations = initialLocations
            if (locations != null) {
                initialLocations = null
                scrollToLocations(locations, toStart = true)
                visualListener.onVisualReaderIsReady()
            }
        }
    }

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator
    ) {
        visualListener.onPageChanged(pageIndex, totalPages, locator)
        state[currentVisualCurrentLocatorKey] = locator
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        visualListener.onExternalLinkActivated(url)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        visualListener.onVisualCurrentLocationChanged(locator)
    }

    override fun dispose() {
        super.dispose()

        epubNavigator?.let { fragment ->
            fragment.parentFragmentManager.commitNow { remove(fragment) }
        }
        epubNavigator = null

        state.clear()
    }

    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator ?: return null

        afterFragmentStarted()
        return navigator.evaluateJavascript(script)
    }

    suspend fun goLeft(animated: Boolean) {
        val navigator = epubNavigator ?: return

        Log.d(TAG, "::goLeft")
        navigator.goLeft(animated)
    }

    suspend fun goRight(animated: Boolean) {
        val navigator = epubNavigator ?: return

        Log.d(TAG, "::goRight")
        navigator.goRight(animated)
    }

    private suspend fun afterFragmentStarted() {
        if (navigatorStarted.value) return

        navigatorStarted.first { it }
    }

    suspend fun isReaderReady(): Boolean {
        return epubNavigator?.isReaderReady() ?: false
    }

    suspend fun getLocatorFragments(locator: Locator): Locator? {
        val json =
            evaluateJavascript("window.epubPage.getLocatorFragments(${locator.toJSON()}, $isVerticalScroll)")
        try {
            if (json == null || json == "null" || json == "undefined") {
                Log.e(
                    TAG,
                    "getLocatorFragments: window.epubPage.getVisibleRange failed!"
                )
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

    suspend fun firstVisibleElementLocator(): Locator? {
        return epubNavigator?.firstVisibleElementLocator()
    }

    fun applyDecorations(
        decorations: List<Decoration>,
        group: String
    ) {
        mainScope.launch {
            epubNavigator?.applyDecorations(decorations, group)
        }
    }

    private suspend fun scrollToLocations(
        locations: Locator.Locations,
        toStart: Boolean
    ) {
        val json = locations.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json, toStart: $toStart")
        evaluateJavascript("window.epubPage.scrollToLocations($json,$isVerticalScroll,$toStart);")
    }

    suspend fun goToLocator(locator: Locator, animated: Boolean) {
        val locations = locator.locations
        val shouldScroll = canScroll(locations)
        val currentHref = currentLocator?.value?.href
        val shouldGo = currentHref?.isEquivalent(locator.href) == false

        if (shouldGo) {
            Log.d(TAG, "::goToLocator: Go to ${locator.href} from ${currentHref}")
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

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle
        ): EpubNavigator {
            val locator = state.getString(currentVisualCurrentLocatorKey)
                ?.let { Locator.fromJSON(JSONObject(it)) }
            val preferences = state.getString(epubPreferencesKey)
                ?.let { Json.decodeFromString<EpubPreferences>(it) } ?: EpubPreferences()

            Log.d(TAG, "::restoreState - locator: $locator, preferences: $preferences");

            return EpubNavigator(publication, locator, listener,preferences)
        }
    }
}