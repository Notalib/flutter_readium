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
import kotlinx.coroutines.flow.MutableStateFlow
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

    private var editor: EpubPreferencesEditor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            Log.d(TAG, "::onCreate $instance - savedInstanceState? = ${savedInstanceState != null} ")

            if (savedInstanceState != null) {
                vm = restoreViewModelFromState(savedInstanceState)
            }

            super.onCreate(null)
        } finally {
            Log.d(TAG, "::onCreate $instance - ended")
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        try {
            Log.d(TAG, "::onCreateView $instance - $savedInstanceState")
            val view = super.onCreateView(inflater, container, savedInstanceState)

            Log.d(TAG, "::onCreateView $instance - $view")
            return view!!
        } finally {
            Log.d(TAG, "::onCreateView $instance - ended")
        }
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
        try {
            Log.d(TAG, "::onResume - $instance - $attachingNavigatorFragment")

            if (vm == null) {
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

            val readerData = vm as? EpubReaderViewModel
            if (readerData == null) {
                Log.d(TAG, "::onViewCreated - $instance - missing reader data")
                return
            }

            // Prevent onResume from attempting to add the navigator while we work.
            attachingNavigatorFragment = true

            lifecycleScope.launch {
                if (readerData.publication == null) {
                    Log.d(TAG, "::onViewCreated - $instance - re-open publication: $attachingNavigatorFragment")

                    readerData.publication = readium.openPublication(readerData.pubUrl).getOrNull()
                    Log.d(
                        TAG,
                        "::onViewCreated - $instance - re-open publication - done - ${readerData.publication}"
                    )
                }

                if (readerData.publication != null) {
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

            vm?.locator = currentLocator?.value

            epubNavigator?.let {
                childFragmentManager.beginTransaction()
                    .remove(it)
                    .commitNow()
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

        val readerData = vm as? EpubReaderViewModel
        if (readerData == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing view model")
            return
        }

        if (readerData.publication == null) {
            Log.e(TAG, "::attachNavigator() - $instance - missing publication")
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

        Log.d(TAG, "::attachNavigator - $instance - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                fragment,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        Log.d(TAG, "::attachNavigator() - $instance - get navigator")
        val nav = childFragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as EpubNavigatorFragment
        navigator = nav
        Log.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true

        lifecycleScope.launch {
            nav.currentLocator.throttleLatest(Duration.parse("1s")).collect { cl ->
                me.vm?.locator = cl
                Log.d(TAG, "::update currentLocator $cl")
            }
        }
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_EPUB_READER_FRAGMENT"
    }
}
