package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.R
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.models.EpubReaderViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl


private const val TAG = "EpubReaderFragment"

private var instanceNo = 0

@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener, CoroutineScope by MainScope() {

    interface Listener {
        fun onPageLoaded()
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
        fun onExternalLinkActivated(url: AbsoluteUrl)
    }

    var listener: Listener? = null

    val started = MutableStateFlow(false)

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

    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::evaluateJavascript. Navigator not ready.")
            return null
        }

        return navigator.evaluateJavascript(script)
    }

    suspend fun isReaderReady(): Boolean {
        return started.value && evaluateJavascript("window.epubPage.isReaderReady();") == "true"
    }

    fun updatePreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::updatePreferences")
        epubNavigator?.submitPreferences(preferences)
    }

    fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        if (navigator.goBackward(animated)) {
            Log.d(TAG, "::goLeft: Went back.")
        } else {
            Log.d(TAG, "::goLeft: Couldn't go back.")
        }
    }

    fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        val navigator = epubNavigator
        if (navigator == null) {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        if (navigator.goForward(animated)) {
            Log.d(TAG, "::goRight: Went forward.")
        } else {
            Log.d(TAG, "::goRight: Couldn't go forward.")
        }
    }

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

    override fun onViewStateRestored(savedInstanceState: Bundle?) {
        try {
            Log.d(TAG, "::onViewStateRestored - $instance")
            super.onViewStateRestored(savedInstanceState)
        } finally {
            Log.d(TAG, "::onViewStateRestored - $instance - ended")
        }
    }

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

    override fun onStart() {
        try {
            Log.d(TAG, "::onStart - $instance")
            super.onStart()
        } finally {
            Log.d(TAG, ":: onStart - $instance - ended")
        }
    }

    override fun onStop() {
        try {
            Log.d(TAG, "::onStop - $instance")
            super.onStop()
        } finally {
            Log.d(TAG, ":: onStop - $instance - ended")
        }
    }

    override fun onDetach() {
        try {
            Log.d(TAG, "::onDetach - $instance")
            super.onDetach()
        } finally {
            Log.d(TAG, "::onDetach - $instance - ended")
        }
    }

    override fun onDestroy() {
        try {
            Log.d(TAG, "::onDestroy - $instance")
            super.onDestroy()
        } finally {
            Log.d(TAG, "::onDestroy - $instance - ended")
        }
    }

    override fun onDestroyView() {
        try {
            Log.d(TAG, "::onDestroyView - $instance")
            super.onDestroyView()
        } finally {
            Log.d(TAG, "::onDestroyView - $instance - ended")
        }
    }

    private var attachingNavigatorFragment = false
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

        val me = this

        // DFG: This will be relative to your app's src/main/assets/ folder.
        // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
        // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
        val preferences = model.preferences ?: EpubPreferences()
        model.preferences = preferences
        val navigatorFactory = model.navigatorFactory!!
        val fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,
                servedAssets = listOf(
                    "flutter_assets/packages/flutter_readium/assets/.*",
                )
            ),
            initialLocator = model.locator,
            listener = me,
            paginationListener = me,
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

        navigator = epubNavigator
        Log.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_EPUB_READER_FRAGMENT"
    }
}
