package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.R
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.models.EpubReaderViewModel
import dk.nota.flutter_readium.models.ViewPortSize
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.OverflowableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.util.DirectionalNavigationAdapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.epub.EpubLayout
import org.readium.r2.shared.publication.presentation.presentation
import org.readium.r2.shared.util.AbsoluteUrl


private const val TAG = "EpubReaderFragment"

private var instanceNo = 0

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener, CoroutineScope by MainScope() {

    interface Listener {
        /**
         * Called when a page has finished loading.
         */
        fun onPageLoaded()

        /**
         * Called when the current page has changed.
         */
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)

        /**
         * Called when an external link is activated.
         */
        fun onExternalLinkActivated(url: AbsoluteUrl)
    }

    var listener: Listener? = null

    val started = MutableStateFlow(false)

    val scrollMode: Boolean
        get() = epubNavigator?.settings?.value?.scroll == true

    val layoutMode =
        ReadiumReader.currentPublication?.metadata?.presentation?.layout ?: EpubLayout.REFLOWABLE

    private val instance = ++instanceNo

    private var epubNavigator
        get() = navigator as? EpubNavigatorFragment
        set(value) {
            navigator = value
        }

    private val epubVm
        get() = vm as EpubReaderViewModel?

    @ExperimentalReadiumApi
    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        listener?.onExternalLinkActivated(url)
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression}"
        )

        listener?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        listener?.onPageLoaded()
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::firstVisibleElementLocator. Navigator not ready.")
            return null
        }

        return navigator.firstVisibleElementLocator()
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::applyDecorations. Navigator not ready.")
            return
        }

        navigator.applyDecorations(decorations, group)
    }

    /**
     * Evaluate JavaScript in the context of the navigator's WebView.
     * NOTE: Returns null on error and if script returns null/undefined.
     */
    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::evaluateJavascript. Navigator not ready.")
            return null
        }

        return navigator.evaluateJavascript(script)
    }

    /**
     * Update the reader preferences.
     */
    fun updatePreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::updatePreferences")
        epubNavigator?.submitPreferences(preferences)
    }

    /**
     * Navigate backward. Readium component handles RTL / LTR
     */
    suspend fun goBackward(animated: Boolean) {
        Log.d(TAG, "::goBackward")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goBackward. Navigator not ready.")
            return
        }

        if (layoutMode != EpubLayout.FIXED && scrollMode) {
            currentLocator?.value?.takeIf {
                it.locations.position != null && it.locations.progression != null
            }?.let { locator ->
                val currentProgression = locator.locations.progression!!

                val viewPortSize = currentViewPortSize()

                val publication = ReadiumReader.currentPublication ?: run {
                    Log.e(TAG, "::goForward - no current publication?")
                    return
                }
                val position = publication.readingOrder.indexOfFirst { it.href.resolve().isEquivalent(locator.href) }

                val prevProgression = viewPortSize.prevProgression
                if (prevProgression < 0.0) {
                    // stepping back gets us before the start of the current file, but if it is less than a full page go to the top.
                    if (position <= 0) {
                        // Reached the beginning
                        return
                    }

                    Log.d(TAG, "::goBackward load prev chapter, progression:$prevProgression")
                    publication.readingOrder[position - 1].let { prevLink ->
                        val locator = publication.locatorFromLink(prevLink)?.copyWithLocations(
                            progression = 1.0,
                            totalProgression = null
                        ) ?: run {
                            Log.d(TAG, "::goBackward - failed to make locator from link")
                            return
                        }
                        navigator.go(locator, animated)
                    }

                    return
                }

                Log.d(
                    TAG,
                    "::goBackward from progression:$currentProgression to $prevProgression"
                )
                navigator.go(locator.copyWithLocations(progression = prevProgression), animated)
                return
            }

            Log.d(TAG, "::goBackward - Reached start?")
            return
        }

        if (navigator.goBackward(animated)) {
            Log.d(TAG, "::goBackward: Went back.")
        } else {
            Log.d(TAG, "::goBackward: Couldn't go back.")
        }
    }

    /**
     * Navigate forward. Readium component handles RTL / LTR
     */
    @OptIn(InternalReadiumApi::class)
    suspend fun goForward(animated: Boolean) {
        Log.d(TAG, "::goForward")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goForward. Navigator not ready.")
            return
        }

        if (layoutMode != EpubLayout.FIXED && scrollMode) {
            currentLocator?.value?.takeIf {
                it.locations.position != null && it.locations.progression != null
            }?.let { locator ->
                val currentProgression = locator.locations.progression!!
                val position = locator.locations.position!!

                val viewPortSize = currentViewPortSize()
                val nextProgression = viewPortSize.nextProgression
                val publication = ReadiumReader.currentPublication ?: run {
                    Log.e(TAG, "::goForward - no current publication?")
                    return
                }

                if (nextProgression >= 1.0) {
                    if (position >= publication.readingOrder.size) {
                        Log.d(TAG, "::goForward - reached end.")
                        return
                    }

                    Log.d(TAG, "::goForward. load next chapter, progression:$nextProgression")

                    publication.readingOrder[position].let { nextLink ->
                        navigator.go(nextLink, animated)
                    }

                    return
                }

                Log.d(TAG, "::goForward from progression:$currentProgression to $nextProgression")
                navigator.evaluateJavascript("readium.scrollToPosition($nextProgression)")
                return
            }

            Log.d(TAG, "::goForward - Reached end?")
            return
        }

        if (navigator.goForward(animated)) {
            Log.d(TAG, "::goForward: Went forward.")
        } else {
            Log.d(TAG, "::goForward: Couldn't go forward.")
        }
    }

    suspend fun currentViewPortSize(): ViewPortSize {
        val viewPortSize = ViewPortSize.fromJson(
            evaluateJavascript("window.flutterReadium.getViewPortSize()") ?: "", scrollMode
        )
        return viewPortSize
    }

    /**
     * Android lifecycle resume method, reattaches the navigator if needed.
     */
    override fun onResume() {
        try {
            Log.d(TAG, "::onResume - $instance - $attachingNavigatorFragment")

            if (epubVm == null) {
                Log.d(TAG, "::onResume - $instance - missing view model")
                return
            }

            if (attachingNavigatorFragment) {
                Log.d(TAG, "::onResume - $instance - don't attach navigator")
                return
            }

            // Recreate/attach the navigator after soft suspend.
            attachNavigator()
        } finally {
            super.onResume()
            Log.d(TAG, "::onResume - $instance - ended")
        }
    }

    /**
     * Android lifecycle view created method, creates and attaches the navigator.
     */
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        try {
            super.onViewCreated(view, savedInstanceState)

            Log.d(TAG, "::onViewCreated - $instance $view, $savedInstanceState")

            val model = epubVm
            if (model == null) {
                Log.d(TAG, "::onViewCreated - $instance - missing reader data")
                return
            }

            // Prevent onResume from attempting to add the navigator while we work.
            attachingNavigatorFragment = true

            lifecycleScope.launch {
                if (ReadiumReader.currentPublication != null) {
                    Log.d(TAG, "::onViewCreated - $instance - attach navigator")
                    attachNavigator()
                } else {
                    Log.d(TAG, "::onViewCreated - $instance - publication is missing")
                }

                attachingNavigatorFragment = false
            }
        } finally {
            Log.d(TAG, "::onViewCreated - $instance - ended")
        }
    }

    /**
     * Android lifecycle pause method, detaches the navigator to save resources and prevent caches.
     */
    override fun onPause() {
        try {
            Log.d(TAG, "::onPause - $instance")

            epubVm?.locator = currentLocator?.value

            epubNavigator?.let { fragment ->
                childFragmentManager.commitNow {
                    remove(fragment)
                }
            }

            epubNavigator = null
            started.value = false

            attachingNavigatorFragment = false

            super.onPause()
        } finally {
            Log.d(TAG, "::onPause - $instance - ended")
        }
    }

    private var attachingNavigatorFragment = false

    /**
     * Attach the navigator fragment to this reader fragment.
     */
    private fun attachNavigator() {
        Log.d(TAG, "::attachNavigator() - $instance")
        if (navigator != null) {
            Log.d(TAG, "::attachNavigator() - $instance - already attached")
            return
        }

        val model = epubVm
        if (model == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing view model")
            return
        }

        if (ReadiumReader.currentPublication == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing publication")
            return
        }

        val preferences = model.preferences ?: EpubPreferences()
        model.preferences = preferences
        val navigatorFactory = model.navigatorFactory!!
        val fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,

                // DFG: This will be relative to your app's src/main/assets/ folder.
                // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
                // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
                servedAssets = listOf(
                    "flutter_assets/packages/flutter_readium/assets/.*",
                )
            ),
            initialLocator = model.locator,
            listener = this,
            paginationListener = this,
            initialPreferences = preferences,
        )

        val epubNavigator = fragmentFactory.instantiate(
            requireActivity().classLoader,
            EpubNavigatorFragment::class.java.name
        ) as EpubNavigatorFragment

        Log.d(TAG, "::attachNavigator - $instance - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                epubNavigator,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        (epubNavigator as OverflowableNavigator).apply {
            // This will automatically turn pages when tapping the screen edges or arrow keys.
            addInputListener(DirectionalNavigationAdapter(this))
        }

        navigator = epubNavigator
        Log.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_EPUB_READER_FRAGMENT"
    }
}
