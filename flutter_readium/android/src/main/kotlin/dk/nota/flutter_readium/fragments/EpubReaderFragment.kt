package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.R
import dk.nota.flutter_readium.StartLifecycleObserver
import dk.nota.flutter_readium.models.EpubReaderViewModel
import dk.nota.flutter_readium.throttleLatest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlin.time.Duration


private const val TAG = "EpubReaderFragment"

private const val epubPreferencesKeyName = "EPubPreferences"

@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener, CoroutineScope by MainScope() {

    interface Listener {
        fun onPageLoaded()
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
        fun onExternalLinkActivated(url: AbsoluteUrl)
    }

    var listener: Listener? = null

    /// Checks when the fragment starts and is safe to use.
    val fragmentObserver = StartLifecycleObserver(TAG)

    private var epubNavigator
        get() = navigator as? EpubNavigatorFragment
        set(value) {
            navigator = value
        }

    private var editor: EpubPreferencesEditor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "::onCreate - savedInstanceState? = ${savedInstanceState != null} ")

        if (savedInstanceState != null) {
            vm = restoreViewModelFromState(savedInstanceState)
        }

        super.onCreate(savedInstanceState)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        Log.d(TAG, "::onCreateView - $savedInstanceState")
        val view = super.onCreateView(inflater, container, savedInstanceState)

        Log.d(TAG, "::onCreateView - done")
        return view!!
    }

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
        if (navigator == null)
        {
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
        if (navigator == null)
        {
            Log.d(TAG, "::applyDecorations. Navigator not ready.")
            return
        }

        navigator.applyDecorations(decorations, group)
    }

    suspend fun evaluateJavascript(script: String): String? {
        val navigator = epubNavigator
        if (navigator == null)
        {
            Log.d(TAG, "::evaluateJavascript. Navigator not ready.")
            return null
        }

        return navigator.evaluateJavascript(script)
    }

    suspend fun setPreferences(preferences: EpubPreferences) {
        Log.d(TAG, "::setPreferences")
        val navigator = epubNavigator
        if (navigator == null)
        {
            Log.d(TAG, "::setPreferences. Navigator not ready.")
            return
        }

        try {
            suspendCoroutine {
                editor?.let {
                    it.apply {
                        fontFamily.set(preferences.fontFamily)
                        fontSize.set(preferences.fontSize)
                        fontWeight.set(preferences.fontWeight)
                        scroll.set(preferences.scroll)
                        backgroundColor.set(preferences.backgroundColor)
                        textColor.set(preferences.textColor)
                    }

                    navigator.submitPreferences(it.preferences)
                }
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    suspend fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        val navigator = epubNavigator
        if (navigator == null)
        {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        suspendCoroutine {
            if (navigator.goBackward(animated)) {
                Log.d(TAG, "::goLeft: Went back.")
            } else {
                Log.d(TAG, "::goLeft: Couldn't go back.")
            }
            it.resume(Unit)
        }
    }

    internal suspend fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        val navigator = epubNavigator
        if (navigator == null)
        {
            Log.d(TAG, "::goLeft. Navigator not ready.")
            return
        }

        suspendCoroutine {
            if (navigator.goForward(animated)) {
                Log.d(TAG, "::goRight: Went forward.")
            } else {
                Log.d(TAG, "::goRight: Couldn't go forward.")
            }

            it.resume(Unit)
        }
    }


    override fun storeViewModelInState(outState: Bundle) {
        super.storeViewModelInState(outState)

        editor?.preferences?.let {
            val jsonString = Json.encodeToString(it)
            outState.putString(epubPreferencesKeyName, jsonString)
            val model = vm as EpubReaderViewModel
            model.preferences = it
        }
    }

    override fun restoreViewModelFromState(savedInstanceState: Bundle): EpubReaderViewModel? {
        val restoredPreferences = savedInstanceState.getString(epubPreferencesKeyName)?.let{ Json.decodeFromString(it) as EpubPreferences } ?: EpubPreferences()

        return super.restoreViewModelFromState(savedInstanceState)?.let {
            val vm = EpubReaderViewModel().apply()
            {
                identifier = it.identifier
                pubUrl = it.pubUrl
                publication = it.publication
                locator = it.locator
                preferences = restoredPreferences
            }

            return vm
        }
    }

    override fun onResume() {
        Log.d(TAG, "::onResume - $attachingNavigatorFragment")

        if (vm == null) {
            Log.d(TAG, "::onResume - missing view model")
            super.onResume()
            return
        }

        if (attachingNavigatorFragment) {
            Log.d(TAG, "::onResume - don't attach navigator")
            super.onResume()
            return
        }

        // Recreate/attach the navigator after soft suspend.
        attachNavigator()
        Log.d(TAG, "::onResume - ended")
        super.onResume()
    }

    override fun onViewStateRestored(savedInstanceState: Bundle?) {
        super.onViewStateRestored(savedInstanceState)
        Log.d(TAG, "::onViewStateRestored - $savedInstanceState")
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        Log.d(TAG, "::onViewCreated $view, $savedInstanceState")

        val readerData = vm as? EpubReaderViewModel
        if (readerData == null)
        {
            Log.d(TAG, "::onViewCreated - missing reader data")
            return
        }

        // Prevent onResume from attempting to add the navigator while we work.
        attachingNavigatorFragment = true
        lifecycleScope.launch {
            if (readerData.publication == null) {
                Log.d(TAG, "::onViewCreated - re-open publication: $attachingNavigatorFragment")

                readerData.publication = readium.openPublication(readerData.pubUrl).getOrNull();
                Log.d(TAG, "::onViewCreated - re-open publication - done - ${readerData.publication}")
            }

            if (readerData.publication != null) {
                Log.d(TAG, "::onViewCreated - attach navigator")
                attachNavigator()
            } else {
                Log.d(TAG, "::onViewCreated - publication is missing")
            }

            attachingNavigatorFragment = false
        }
    }

    override fun onPause() {
        Log.d(TAG, "::onPause")

        vm?.locator = currentLocator?.value

        epubNavigator?.let {
            childFragmentManager.beginTransaction()
                .remove(it)
                .commitNow()

            it.lifecycle.removeObserver(fragmentObserver)
        }

        epubNavigator = null
        fragmentObserver.started.value = false
        attachingNavigatorFragment = false

        super.onPause()
    }

    override fun onStop() {
        Log.d(TAG, "::onStop")
        super.onStop()
    }

    override fun onDetach() {
        Log.d(TAG, "::onDetach")
        super.onDetach()
    }

    override fun onDestroy() {
        Log.d(TAG, "::onDestroy")
        super.onDestroy()
    }

    override fun onDestroyView() {
        Log.d(TAG, "::onDestroyView")
        super.onDestroyView()
    }

    private var attachingNavigatorFragment = false
    private fun attachNavigator() {
        Log.d(TAG, "::attachNavigator()")
        if (navigator != null) {
            Log.d(TAG, "::attachNavigator() - already attached")
            return
        }

        val readerData = vm as? EpubReaderViewModel
        if (readerData == null) {
            Log.e(TAG, "::attachNavigator() - missing view model")
            return
        }

        if (readerData.publication == null) {
            Log.e(TAG, "::attachNavigator() - missing publication")
            return
        }

        val me = this

        // DFG: This will be relative to your app's src/main/assets/ folder.
        // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
        // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
        readerData.preferences = readerData.preferences ?: EpubPreferences()
        val preferences = readerData.preferences ?: EpubPreferences()
        val navigatorFactory = readerData.navigatorFactory!!
        editor = navigatorFactory.createPreferencesEditor(preferences)
        val fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,
                servedAssets = listOf(
                    "flutter_assets/packages/flutter_readium/assets/.*",
                )
            ),
            initialLocator = readerData.locator,
            listener = me,
            paginationListener = me,
            initialPreferences = preferences,
        )

        val fragment = fragmentFactory.instantiate(requireActivity().classLoader, EpubNavigatorFragment::class.java.name)

        Log.d(TAG, "::attachNavigator - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                fragment,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        Log.d(TAG, "::attachNavigator - get navigator")
        val nav = childFragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as EpubNavigatorFragment;
        navigator = nav
        Log.d(TAG, "::attachNavigator - got navigator = $navigator")

        nav.lifecycle.addObserver(fragmentObserver)
        Log.d(TAG, "::attachNavigator - addObserver")

        lifecycleScope.launch {
            nav.currentLocator.throttleLatest(Duration.parse("1s")).collect { cl ->
                me.vm?.locator = cl
                Log.d(TAG, "::update currentLocator $cl")
            }
        }
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "navigator"
    }
}
