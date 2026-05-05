package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dk.nota.flutter_readium.FlutterEpubPreferences
import dk.nota.flutter_readium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.models.EpubReaderViewModel
import dk.nota.flutter_readium.throttleLatest
import dk.nota.flutter_readium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "EpubNavigator"
private const val currentVisualLocatorKey = "currentVisualCurrentLocator"

private const val epubPreferencesKey = "epubPreferences"

private const val currentDecorationListKey = "currentDecorationsList"

/**
 * EpubNavigator is a wrapper around the EpubReaderFragment and provides methods to interact with it.
 * It also listens to events from the fragment and forwards them to the VisualListener.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubNavigator :
    BaseNavigator,
    EpubReaderFragment.Listener {
    constructor(
        publication: Publication,
        initialLocator: Locator?,
        visualListener: VisualListener,
        initialPreferences: FlutterEpubPreferences = FlutterEpubPreferences(),
        initialDecorations: MutableMap<String, List<Decoration>> = mutableMapOf(),
    ) : super(publication, initialLocator) {
        this.preferences = initialPreferences
        this.visualListener = visualListener
        this.currentDecorations = initialDecorations
        this.currentVisualLocator = initialLocator
    }

    private var currentDecorations: MutableMap<String, List<Decoration>> = mutableMapOf()

    val visualListener: VisualListener

    private var currentVisualLocator: Locator?
        get() = state[currentVisualLocatorKey] as? Locator
        set(value) {
            state[currentVisualLocatorKey] = value
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
        fun onPageChanged(
            pageIndex: Int,
            totalPages: Int,
            locator: Locator,
        )

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

    /**
     * EpubReaderFragment instance used as navigator.
     */
    private var epubNavigator: EpubReaderFragment? = null

    /**
     * Current EPUB preferences.
     */
    var preferences: FlutterEpubPreferences?
        get() = state[epubPreferencesKey] as? FlutterEpubPreferences
        set(value) {
            state[epubPreferencesKey] = value
        }

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

    override suspend fun initNavigator() {
        epubNavigator =
            EpubReaderFragment().apply {
                vm =
                    EpubReaderViewModel().apply {
                        navigatorFactory = EpubNavigatorFactory(publication)
                        locator = this@EpubNavigator.initialLocator
                        preferences = this@EpubNavigator.preferences
                    }
                listener = this@EpubNavigator
            }
    }

    /**
     * Attach the EPUB navigator fragment to the given FragmentManager and ViewGroup.
     */
    fun attachNavigator(
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
    ) {
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
    suspend fun go(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    ): Boolean {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::go - epubNavigator is null!")
            return false
        }

        Log.d(TAG, "::go $locator animated:$animated")

        return withScope(mainScope) {
            afterFragmentStarted()
            segmentDuration?.takeIf { it > 0 }?.let {
                navigator.evaluateJavascript("window.flutterReadium.setSegmentDuration(${it * 1000.0})")
            }

            if (!navigator.go(locator, animated)) {
                Log.w(TAG, "::go -  FAILED!")
                return@withScope false
            }

            Log.d(TAG, "::go - returned true")

            return@withScope true
        }
    }

    suspend fun scrollToProgression(progression: Double) {
        val navigator =
            epubNavigator ?: run {
                Log.e(TAG, "::scrollToProgression - epubNavigator is null")

                return
            }

        navigator.scrollToProgression(progression)
    }

    /**
     * Update EPUB navigator preferences.
     */
    suspend fun updatePreferences(flutterEpubPreferences: FlutterEpubPreferences) {
        Log.d(TAG, "::updatePreferences")

        val navigator =
            epubNavigator ?: run {
                Log.d(TAG, "Tried to update preferences without a navigator")
                preferences = flutterEpubPreferences
                return
            }

        try {
            navigator.updatePreferences(flutterEpubPreferences)

            preferences = flutterEpubPreferences
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    override fun setupNavigatorListeners() {
        val navigator =
            epubNavigator ?: run {
                Log.e(TAG, "::setupNavigatorListeners - epubNavigator is null this should never happen")
                return
            }

        val currentLocator = navigator.currentLocator
        if (currentLocator != null) {
            currentLocator
                .throttleLatest(100.milliseconds)
                .distinctUntilChanged()
                .onEach { locator ->
                    onCurrentLocatorChanges(locator)
                    currentVisualLocator = locator
                }.launchIn(mainScope)
                .let { jobs.add(it) }
        } else {
            Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
        }
    }

    override fun storeState(): Bundle =
        Bundle().apply {
            putString(
                currentVisualLocatorKey,
                currentVisualLocator?.toJSON()?.toString(),
            )

            currentDecorations.takeIf { it.isNotEmpty() }?.let { decorations ->
                val decorationBundle = Bundle()

                decorations.forEach { (key, value) ->
                    decorationBundle.putParcelableArrayList(
                        key,
                        ArrayList(value),
                    )
                }

                putBundle(currentDecorationListKey, decorationBundle)
            }

            preferences?.let { prefs ->
                putString(
                    epubPreferencesKey,
                    Json.encodeToString(FlutterEpubPreferences.serializer(), prefs),
                )
            }
        }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")

        visualListener.onPageLoaded()

        notifyIsReady()

        mainScope.launch {
            currentDecorations.forEach { (group, decorations) ->
                epubNavigator?.applyDecorations(
                    decorations = decorations,
                    group = group,
                )
            }
        }
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
        locator: Locator,
    ) {
        visualListener.onPageChanged(pageIndex, totalPages, locator)

        mainScope.launch {
            if (currentVisualLocator?.href != locator.href) {
                // Since the visual href changed, we clear old decorations.
                // This should remove stale decorations from the old file when switching back
                // and forth between the files.
                epubNavigator?.let { navigator ->
                    currentDecorations.keys.forEach { group ->
                        navigator.applyDecorations(
                            listOf(),
                            group,
                        )
                    }
                }
            }

            currentVisualLocator = locator
        }
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

    /**
     * Navigate backward. Readium component handles RTL / LTR
     */
    suspend fun goBackward(animated: Boolean = true) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goBackward - epubNavigator is null!")
            return
        }

        withScope(mainScope) {
            Log.d(TAG, "::goBackward")
            navigator.goBackward(animated)
        }
    }

    /**
     * Navigate forward. Readium component handles RTL / LTR
     */
    suspend fun goForward(animated: Boolean = true) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.e(TAG, "::goForward - epubNavigator is null!")
            return
        }

        withScope(mainScope) {
            Log.d(TAG, "::goForward")
            navigator.goForward(animated)
        }
    }

    private suspend fun afterFragmentStarted() {
        if (navigatorStarted.value) return

        navigatorStarted.first { it }
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator =
            epubNavigator ?: run {
                Log.e(TAG, "::firstVisibleElementLocator - epubNavigator is null!")
                return null
            }

        return withScope(mainScope) {
            navigator.firstVisibleElementLocator()
        }
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator =
            epubNavigator ?: run {
                Log.e(TAG, "::applyDecorations: navigator is null")
                return
            }

        withScope(mainScope) {
            Log.d(TAG, "::applyDecorations: $decorations for group:$group")

            navigator.applyDecorations(decorations, group)

            if (decorations.isNotEmpty()) {
                currentDecorations[group] = decorations
            } else {
                currentDecorations.remove(group)
            }
        }
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun goToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double? = null,
    ) {
        withScope(mainScope) {
            go(locator, animated, segmentDuration)
        }
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: VisualListener,
            state: Bundle,
        ): EpubNavigator {
            val locator =
                state
                    .getString(currentVisualLocatorKey)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences =
                state
                    .getString(epubPreferencesKey)
                    ?.let { string -> Json.decodeFromString<FlutterEpubPreferences>(string) }
                    ?: FlutterEpubPreferences()

            val currentDecorations = mutableMapOf<String, List<Decoration>>()
            state.getBundle(currentDecorationListKey)?.let { bundle ->
                for (key in bundle.keySet()) {
                    val list: ArrayList<Decoration>? = bundle.getParcelableArrayList(key)
                    if (list != null) currentDecorations[key] = list
                }
            }

            Log.d(TAG, "::restoreState - locator: $locator, preferences: $preferences")

            return EpubNavigator(publication, locator, listener, preferences, currentDecorations)
        }
    }
}
