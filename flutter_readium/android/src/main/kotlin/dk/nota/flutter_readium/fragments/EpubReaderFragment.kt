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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private const val TAG = "EpubReaderFragment"

@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment : VisualReaderFragment(), EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener, CoroutineScope by MainScope() {

    interface Listener {
        fun onPageLoaded()
        fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
        fun onExternalLinkActivated(url: AbsoluteUrl)
    }

    var listener: Listener? = null

    override lateinit var navigator: EpubNavigatorFragment

    /// Checks when the fragment starts and is safe to use.
    val fragmentObserver = StartLifecycleObserver(TAG)

    val currentLocator get() = navigator.currentLocator

    private var editor: EpubPreferencesEditor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "::onCreate - savedInstanceState? = ${savedInstanceState != null}")
        /*
        if (savedInstanceState != null) {
            Log.d(TAG, "::onCreate - restore pub 1")

            lifecycleScope.launch {
                try {
                    val pState = restorePublicationFromState(savedInstanceState)
                    if (pState?.publication != null) {
                        Log.d(TAG, "Restored: ${pState.identifier}")

                        vm = EpubReaderViewModel().let {
                            it.publication = pState.publication
                            it.identifier = pState.identifier

                            it
                        }
                    }
                } catch(error: Exception) {
                    Log.d(TAG, "Failed to restore publication")
                }
            }

            Log.d(TAG, "::onCreate - restore pub 2")

            super.onCreate(savedInstanceState)
            return
        }
*/
        val readerData = vm as? EpubReaderViewModel ?: run {
            Log.d(TAG, "::onCreate - restore - dummy factory")
            // We provide a dummy fragment factory  if the ReaderActivity is restored after the
            // app process was killed because the ReaderRepository is empty. In that case, finish
            // the activity as soon as possible and go back to the previous one.
            // Note: this causes a restart of the app to the main activity.
            childFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
            super.onCreate(savedInstanceState)
            val activity = requireActivity()
            val indent = activity.intent
            activity.finish()
            activity.startActivity(indent)
            return
        }

        if (readerData.publication == null) {
            Log.d(TAG, "::onCreate - restore: readium - no restored publication")
            // We provide a dummy fragment factory  if the ReaderActivity is restored after the
            // app process was killed because the ReaderRepository is empty. In that case, finish
            // the activity as soon as possible and go back to the previous one.
            // Note: this causes a restart of the app to the main activity.
            childFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
            super.onCreate(savedInstanceState)
            requireActivity().finish()
            return
        }

        Log.d(TAG, "::onCreate")

        // DFG: This will be relative to your app's src/main/assets/ folder.
        // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
        // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
        readerData.preferences = readerData.preferences ?: EpubPreferences();
        val preferences = readerData.preferences ?: EpubPreferences()
        val navigatorFactory = readerData.navigatorFactory!!
        editor = navigatorFactory.createPreferencesEditor(preferences)
        childFragmentManager.fragmentFactory = navigatorFactory.createFragmentFactory(
            configuration = EpubNavigatorFragment.Configuration(
                shouldApplyInsetsPadding = false,
                servedAssets = listOf(
                    "flutter_assets/packages/flutter_readium/assets/.*",
                )
            ),
            initialLocator = readerData.locator,
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

        Log.d(TAG, "::onCreateView")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                EpubNavigatorFragment::class.java,
                Bundle(),
                NAVIGATOR_FRAGMENT_TAG,
            )
        }/*
        if (savedInstanceState == null) {
            Log.d(TAG, "::onCreateView - add fragment")
            childFragmentManager.commitNow {
                add(
                    R.id.fragment_reader_container,
                    EpubNavigatorFragment::class.java,
                    Bundle(),
                    NAVIGATOR_FRAGMENT_TAG,
                )
            }
        } else {
            Log.d(TAG, "::onCreateView - no add fragment")
            return view!!
        }*/

        navigator = childFragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as EpubNavigatorFragment

        // TODO: Do we risk multiple observers here?
        navigator.lifecycle.addObserver(fragmentObserver)

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
        Log.d(TAG, "::setPreferences")

        try {
            editor?.let {
                val e = it
                it.apply {
                    fontFamily.set(preferences.fontFamily)
                    fontSize.set(preferences.fontSize)
                    fontWeight.set(preferences.fontWeight)
                    scroll.set(preferences.scroll)
                    backgroundColor.set(preferences.backgroundColor)
                    textColor.set(preferences.textColor)
                }
                suspendCoroutine {
                    navigator.submitPreferences(e.preferences)
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
