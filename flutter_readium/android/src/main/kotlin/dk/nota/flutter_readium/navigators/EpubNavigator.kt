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
import dk.nota.flutter_readium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
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
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "EpubNavigator"
private const val currentVisualCurrentLocatorKey = "currentVisualCurrentLocator"
private const val epubPreferencesKey = "epubPreferences"

/**
 * EpubNavigator is a wrapper around the EpubReaderFragment and provides methods to interact with it.
 * It also listens to events from the fragment and forwards them to the VisualListener.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubNavigator : BaseNavigator, EpubReaderFragment.Listener {
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

    /**
     * A VisualListener is used to listen to events from the Visual navigators like EpubNavigator.
     */
    interface VisualListener {
        /**
         * Called when a page has loaded. Note: not necessarily the visible content, since
         * the Readium Navigator preloads neighboring charters.
         */
        fun onPageLoaded()

        /**
         * Called when the current page has changed. Can be a new file or a new page in the
         * same file.
         */
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        /**
         * Called when an external link has been tapped.
         */
        fun onExternalLinkActivated(url: AbsoluteUrl)

        /**
         * Called when the current locator has changed.
         */
        fun onVisualCurrentLocationChanged(locator: Locator)

        /**
         * Called when the visual reader is ready.
         */
        fun onVisualReaderIsReady()
    }

    val visualListener: VisualListener

    /**
     * EpubReaderFragment instance used as navigator.
     */
    private var epubNavigator: EpubReaderFragment? = null

    /**
     * Editor to modify EPUB preferences.
     */
    private var editor: EpubPreferencesEditor? = null

    /**
     * Pending scroll target to be applied when the page is loaded.
     */
    var pendingScrollToLocations: Locator.Locations? = null

    /**
     * Current EPUB preferences.
     */
    val preferences: EpubPreferences?
        get() = editor?.preferences

    /**
     * Current locator in the EPUB navigator.
     */
    val currentLocator
        get() = epubNavigator?.currentLocator

    /**
     * Checks when the fragment starts and is safe to use.
     */
    private val navigatorStarted
        get() = epubNavigator!!.started

    /**
     * Whether the EPUB navigator is in vertical scroll mode.
     */
    private val isVerticalScroll: Boolean
        get() {
            return editor?.preferences?.scroll ?: false
        }

    override suspend fun initNavigator() {
        pendingScrollToLocations =
            initialLocator?.locations?.let { locations ->
                if (canScroll(locations)) locations else null
            }

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

    /**
     * Attach the EPUB navigator fragment to the given FragmentManager and ViewGroup.
     */
    fun attachNavigator(fragmentManager: FragmentManager, viewGroup: ViewGroup) {
        val navigator = epubNavigator ?: return
        mainScope.launch {
            fragmentManager.commitNow {
                add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
            }
        }
    }

    /**
     * Go to a specific locator in the EPUB navigator, this does not scroll to the locator position.
     */
    suspend fun go(locator: Locator, animated: Boolean): Boolean {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::go - epubNavigator is null!")
            return false
        }

        return withScope(mainScope) {
            afterFragmentStarted()
            if (!navigator.go(locator, animated)) {
                Log.w(TAG, "::go -  FAILED!")
                return@withScope false
            }

            Log.d(TAG, "::go - returned true")

            return@withScope true
        }
    }

    /**
     * Update EPUB navigator preferences.
     */
    fun updatePreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::setPreferences")

        try {
            editor?.apply {
                fontFamily.set(preferences.fontFamily)
                fontSize.set(preferences.fontSize)
                fontWeight.set(preferences.fontWeight)
                scroll.set(preferences.scroll)
                backgroundColor.set(preferences.backgroundColor)
                textColor.set(preferences.textColor)

                mainScope.launch {
                    epubNavigator?.updatePreferences(preferences)
                }
                state[epubPreferencesKey] = preferences
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::setupNavigatorListeners - epubNavigator is null this should never happen")
            return
        }

        val currentLocator = navigator.currentLocator
        if (currentLocator != null) {
            currentLocator.throttleLatest(100.milliseconds)
                .distinctUntilChanged()
                .onEach { locator ->
                    onCurrentLocatorChanges(locator)
                    state[currentVisualCurrentLocatorKey] = locator
                }
                .launchIn(mainScope)
                .let { jobs.add(it) }
        } else {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
        }
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

        pendingScrollToLocations?.let { locations ->
            Log.d(TAG, "::onPageLoaded - pendingScrollToLocations: $locations")

            mainScope.async {
                scrollToLocations(locations, toStart = true)
            }

            pendingScrollToLocations = null

        }

        notifyIsReady()
    }

    private var hasNotifiedIsReady = false

    /**
     * Notify that the navigator is ready only once.
     */
    private fun notifyIsReady() {
        if (hasNotifiedIsReady) return

        hasNotifiedIsReady = true
        visualListener.onVisualReaderIsReady()
        setupNavigatorListeners()
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

        mainScope.launch {
            epubNavigator?.let { fragment ->
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }

            mainScope.coroutineContext.cancelChildren()
            epubNavigator = null
        }

        state.clear()
    }

    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::evaluateJavascript - epubNavigator is null!")
            return null
        }

        afterFragmentStarted()
        return withScope(mainScope) {
            navigator.evaluateJavascript(script)
        }
    }

    fun goLeft(animated: Boolean) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goLeft - epubNavigator is null!")
            return
        }

        Log.d(TAG, "::goLeft")
        navigator.goLeft(animated)
    }

    fun goRight(animated: Boolean) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goRight - epubNavigator is null!")
            return
        }

        Log.d(TAG, "::goRight")
        navigator.goRight(animated)
    }

    private suspend fun afterFragmentStarted() {
        if (navigatorStarted.value) return

        navigatorStarted.first { it }
    }

    suspend fun isReaderReady(): Boolean {
        return withScope(mainScope) {
            epubNavigator?.isReaderReady() ?: false
        }
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
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::firstVisibleElementLocator - epubNavigator is null!")
            return null
        }

        return withScope(mainScope) {
            navigator.firstVisibleElementLocator()
        }
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String
    ) {
        mainScope.async {
            epubNavigator?.applyDecorations(decorations, group)
        }.await()
    }

    private suspend fun scrollToLocations(
        locations: Locator.Locations,
        toStart: Boolean
    ) {
        val json = locations.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json, toStart: $toStart")
        evaluateJavascript("window.epubPage.scrollToLocations($json,$isVerticalScroll,$toStart);")
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun goToLocator(locator: Locator, animated: Boolean) {
        mainScope.async {
            val locations = locator.locations
            val shouldScroll = canScroll(locations)
            val locatorHref = locator.href
            val currentHref = currentLocator?.value?.href
            val shouldGo = currentHref?.isEquivalent(locatorHref) == false

            if (shouldGo) {
                Log.d(TAG, "::goToLocator: Go to $locatorHref from $currentHref")
                pendingScrollToLocations = locations
                go(locator, animated)
            } else if (!shouldScroll) {
                Log.w(TAG, "::goToLocator: Already at $locatorHref, no scroll target, go to start")
                scrollToLocations(Locator.Locations(progression = 0.0), true)
            } else {
                Log.d(TAG, "::goToLocator: Already at $locatorHref, scroll to position")

                scrollToLocations(locations, false)
            }
        }.await()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle
        ): EpubNavigator {
            val locator = state.getString(currentVisualCurrentLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(epubPreferencesKey)
                ?.let { string -> Json.decodeFromString<EpubPreferences>(string) }
                ?: EpubPreferences()

            Log.d(TAG, "::restoreState - locator: $locator, preferences: $preferences")

            return EpubNavigator(publication, locator, listener, preferences)
        }
    }
}
