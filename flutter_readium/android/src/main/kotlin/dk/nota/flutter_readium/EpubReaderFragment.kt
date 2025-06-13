package dk.nota.flutter_readium

import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.commitNow
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private const val TAG = "EpubReaderFragment"

@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment(model: ReaderInitData, private val listener: Listener) : VisualReaderFragment(model), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener {

    interface Listener {
        fun onPageLoaded()
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
    }

    override lateinit var navigator: EpubNavigatorFragment

    /// Checks when the fragment starts and is safe to use.
    val fragmentObserver = StartLifecycleObserver(TAG)

    val currentLocator get() = navigator.currentLocator

    private var editor: EpubPreferencesEditor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val readerData = model as? EpubReaderInitData ?: run {
            // We provide a dummy fragment factory  if the ReaderActivity is restored after the
            // app process was killed because the ReaderRepository is empty. In that case, finish
            // the activity as soon as possible and go back to the previous one.
            childFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
            super.onCreate(savedInstanceState)
            requireActivity().finish()
            return
        }

        // DFG: This will be relative to your app's src/main/assets/ folder.
        // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
        // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
        val preferences = readerData.initialPreferences ?: EpubPreferences()
        val navigatorFactory = model.navigatorFactory
        editor = navigatorFactory.createPreferencesEditor(preferences)
        childFragmentManager.fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,
                servedAssets = listOf(
                    "flutter_assets/packages/flutter_readium/assets/.*",
                )
            ),
            initialLocator = model.initialLocation,
            listener = this,
            paginationListener = this,
            initialPreferences = preferences,
        )

        super.onCreate(savedInstanceState)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val view = super.onCreateView(inflater, container, savedInstanceState)

        if (savedInstanceState == null) {
            childFragmentManager.commitNow {
                add(
                    R.id.fragment_reader_container,
                    EpubNavigatorFragment::class.java,
                    Bundle(),
                    NAVIGATOR_FRAGMENT_TAG,
                )
            }
        }

        navigator = childFragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as EpubNavigatorFragment

        navigator.lifecycle.addObserver(fragmentObserver)

        return view!!
    }

    @ExperimentalReadiumApi
    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        TODO("Not yet implemented")
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression}"
        )
        listener.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
        listener.onPageLoaded()
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        return navigator.firstVisibleElementLocator()
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        navigator.applyDecorations(decorations, group)
    }

    suspend fun evaluateJavascript(script: String): String? {
        return navigator.evaluateJavascript(script)
    }

    suspend fun setPreferences(preferences: EpubPreferences) {
        try {
            editor?.apply {
                fontFamily.set(preferences.fontFamily)
                fontSize.set(preferences.fontSize)
                fontWeight.set(preferences.fontWeight)
                scroll.set(preferences.scroll)
                backgroundColor.set(preferences.backgroundColor)
                textColor.set(preferences.textColor)
            }
            suspendCoroutine {
                editor?.let {
                    navigator.submitPreferences(it.preferences)
                }
            }
        } catch (ex: Exception) {
            Log.e(TAG, "Error applying EpubPreferences: $ex")
        }
    }

    suspend fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        suspendCoroutine {
            if (navigator.goBackward(animated)) {
                Log.d(TAG, "::goLeft: Went back.")
                it.resume(Unit)
            } else {
                Log.d(TAG, "::goLeft: Couldn't go back.")
                it.resume(Unit)
            }
        }
    }
    internal suspend fun goRight(animated: Boolean) {
        Log.d(TAG, "::goRight")
        suspendCoroutine {
            if (navigator.goForward(animated)) {
                Log.d(TAG, "::goRight: Went forward.")
                it.resume(Unit)
            } else {
                Log.d(TAG, "::goRight: Couldn't go forward.")
                it.resume(Unit)
            }
        }
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "navigator"
    }
}
