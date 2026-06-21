package dk.nota.flutterreadium.navigators

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.view.ViewCompat
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import androidx.viewpager.widget.ViewPager
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dk.nota.flutterreadium.throttleLatest
import dk.nota.flutterreadium.withMainContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.image.ImageNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.indexOfFirstWithHref
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "ComicNavigator"
private const val currentVisualLocatorKey = "currentVisualCurrentLocator"

/**
 * Wraps the Readium [ImageNavigatorFragment] for bitmap-based publications (CBZ / DiViNa)
 * inside the same [FlutterVisualNavigator] shape used by [EpubNavigator] and [PdfNavigator],
 * so [dk.nota.flutterreadium.ReadiumReader] and
 * [dk.nota.flutterreadium.ReadiumReaderWidget] can treat all three interchangeably.
 *
 * Android uses the dedicated [ImageNavigatorFragment] (not the EPUB navigator) because
 * kotlin-toolkit 3.2.0 ships a non-deprecated, purpose-built image navigator. This differs
 * from swift-toolkit, where CBZ was folded into [EPUBNavigatorViewController].
 *
 * Black-and-white comic mode: NOT implemented for Android.
 * [ImageNavigatorFragment] renders images in native [android.widget.ImageView]s, so iOS's CSS
 * `filter: grayscale()` approach does not apply. A [android.graphics.ColorMatrixColorFilter]
 * could theoretically be applied to child views of the fragment's ViewPager, but there is no
 * clean public hook — doing so would require fragile reflection or walking the view tree after
 * each page change. Per the project's "honest limitations over brittle workarounds" guideline,
 * this is left unimplemented. File an issue if a clean upstream hook becomes available.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class ComicNavigator :
    BaseNavigator,
    ImageNavigatorFragment.Listener,
    FlutterVisualNavigator {
    constructor(
        publication: Publication,
        initialLocator: Locator?,
        visualListener: EpubNavigator.VisualListener,
    ) : super(publication, initialLocator) {
        this.visualListener = visualListener
        this.currentVisualLocator = initialLocator
    }

    val visualListener: EpubNavigator.VisualListener

    private var currentVisualLocator: Locator?
        get() = state[currentVisualLocatorKey] as? Locator
        set(value) {
            state[currentVisualLocatorKey] = value
        }

    private var imageNavigator: ImageNavigatorFragment? = null
    private var pagerInsetsListenerInstalled = false

    override val currentLocator: StateFlow<Locator?>?
        get() = imageNavigator?.currentLocator

    override suspend fun initNavigator() {
        // ImageNavigatorFragment has an internal constructor, so instantiate it via the
        // Readium-provided factory up-front (mirrors how PdfNavigator builds its fragment).
        val factory =
            ImageNavigatorFragment.createFactory(
                publication = publication,
                initialLocator = initialLocator,
                listener = this,
            )
        imageNavigator =
            factory.instantiate(
                ImageNavigatorFragment::class.java.classLoader!!,
                ImageNavigatorFragment::class.java.name,
            ) as ImageNavigatorFragment
    }

    override fun attachNavigator(
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
    ) {
        val navigator =
            imageNavigator ?: run {
                PluginLog.e(TAG, "::attachNavigator. Navigator not initialized — initNavigator() not called?")
                return
            }
        launch {
            // Add by ViewGroup reference, not container id: the plugin's platform-view
            // container has no id resolvable by this FragmentManager, so the id-based add()
            // form fails with "No view found for id". Matches PdfNavigator.attachNavigator.
            fragmentManager.commitNow {
                add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
            }
            // ImageNavigatorFragment's root (a KeyInterceptorView) is added with default
            // wrap_content layout params, which collapses its match_parent descendants
            // (R2ViewPager / PhotoView) to 0x0 and renders nothing. Force the root to fill
            // the platform-view container so the pages get measured and drawn. (EPUB/PDF use
            // host fragments whose root layout is already match_parent, so they avoid this.)
            //
            // Use the parent's concrete LayoutParams subtype. The plugin renders platform views
            // with TLHC (initSurfaceAndroidView), whose container is a FrameLayout — the generic
            // ViewGroup.LayoutParams branch handles that. The LinearLayout branch is a safety net
            // for Hybrid Composition (which TLHC can fall back to per-frame, or a host may select):
            // LinearLayout.measureHorizontal casts params to LinearLayout.LayoutParams and would
            // crash on a generic ViewGroup.LayoutParams.
            navigator.view?.let { v ->
                v.layoutParams =
                    if (v.parent is LinearLayout) {
                        LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        )
                    } else {
                        ViewGroup.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        )
                    }
            }
            setupNavigatorListeners()
            // Comics should be full-bleed in Flutter; strip native cutout/safe-area
            // padding here so Android doesn't reintroduce device-specific insets.
            // TODO(upstream): Ask Readium to add an ImageNavigatorFragment/R2CbzPageFragment
            // equivalent of EpubNavigatorFragment.Configuration.shouldApplyInsetsPadding,
            // then replace this post-layout workaround with that configuration flag.
            installPagerInsetsListener()
            reapplyComicInsetsFix()
        }
    }

    private fun installPagerInsetsListener() {
        if (pagerInsetsListenerInstalled) return

        val root = imageNavigator?.view ?: return
        val pager = findViewPager(root) ?: return

        pager.addOnPageChangeListener(
            object : ViewPager.SimpleOnPageChangeListener() {
                override fun onPageScrollStateChanged(state: Int) {
                    if (state == ViewPager.SCROLL_STATE_IDLE) {
                        reapplyComicInsetsFix()
                    }
                }
            },
        )
        pagerInsetsListenerInstalled = true
    }

    private fun findViewPager(view: View?): ViewPager? {
        if (view == null) return null
        if (view is ViewPager) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findViewPager(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun reapplyComicInsetsFix() {
        imageNavigator?.view?.post {
            clearComicInsets(imageNavigator?.view)
            logViewTree(imageNavigator?.view)
        }
    }

    private fun clearComicInsets(view: View?) {
        if (view == null) return

        if (view.javaClass.simpleName == "PhotoView" && (
                view.paddingTop != 0 ||
                    view.paddingBottom != 0 ||
                    view.paddingLeft != 0 ||
                    view.paddingRight != 0
            )
        ) {
            view.setPadding(0, 0, 0, 0)
        }

        if (view is ViewGroup) {
            val hasPagerChild =
                (0 until view.childCount).any { index ->
                    view.getChildAt(index).javaClass.simpleName == "R2ViewPager"
                }
            if (hasPagerChild) {
                ViewCompat.setOnApplyWindowInsetsListener(view) { _, insets -> insets }
            }

            for (i in 0 until view.childCount) {
                clearComicInsets(view.getChildAt(i))
            }
        }
    }

    private fun logViewTree(
        view: View?,
        depth: Int = 0,
    ) {
        val indent = "  ".repeat(depth)
        if (view == null) {
            PluginLog.d(TAG, "::logViewTree ${indent}null")
            return
        }

        PluginLog.d(
            TAG,
            "::logViewTree $indent${view.javaClass.simpleName} " +
                "bounds=${view.left},${view.top},${view.right},${view.bottom} " +
                "measured=${view.measuredWidth}x${view.measuredHeight} " +
                "padding=${view.paddingLeft},${view.paddingTop},${view.paddingRight},${view.paddingBottom} " +
                "lp=${view.layoutParams?.javaClass?.simpleName}",
        )

        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                logViewTree(view.getChildAt(i), depth + 1)
            }
        }
    }

    override suspend fun goToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double?,
    ) {
        val navigator =
            imageNavigator ?: run {
                PluginLog.w(TAG, "::goToLocator. Navigator not ready.")
                return
            }
        return withMainContext {
            navigator.go(locator, animated)
        }
    }

    override suspend fun goForward(animated: Boolean) {
        val navigator =
            imageNavigator ?: run {
                PluginLog.w(TAG, "::goForward. Navigator not ready.")
                return
            }
        withMainContext {
            navigator.goForward(animated)
        }
    }

    override suspend fun goBackward(animated: Boolean) {
        val navigator =
            imageNavigator ?: run {
                PluginLog.w(TAG, "::goBackward. Navigator not ready.")
                return
            }
        withMainContext {
            navigator.goBackward(animated)
        }
    }

    override suspend fun scrollToProgression(progression: Double) {
        // ImageNavigatorFragment is strictly paginated (one image per page); fractional
        // progression cannot be applied within a page. Map the progression to the nearest
        // reading-order index and jump to that page, matching PdfNavigator's approach.
        val totalResources = publication.readingOrder.size
        if (totalResources == 0) {
            PluginLog.w(TAG, "::scrollToProgression. Reading order is empty.")
            return
        }
        val coerced = progression.coerceIn(0.0, 1.0)
        val targetIndex = (Math.round(coerced * (totalResources - 1))).toInt().coerceIn(0, totalResources - 1)
        val link = publication.readingOrder.getOrNull(targetIndex) ?: return
        PluginLog.d(TAG, "::scrollToProgression. progression=$coerced -> index $targetIndex/$totalResources")

        val navigator =
            imageNavigator ?: run {
                PluginLog.w(TAG, "::scrollToProgression. Navigator not ready.")
                return
            }
        withMainContext {
            navigator.go(link, animated = false)
        }
    }

    override fun setupNavigatorListeners() {
        val navigator =
            imageNavigator ?: run {
                PluginLog.e(TAG, "::setupNavigatorListeners. imageNavigator is null — should never happen")
                return
            }

        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                currentVisualLocator = locator
            }.launchIn(this)
            .let { jobs.add(it) }

        // Emit the initial ready signal + first page-changed event based on the initial locator.
        val initial = navigator.currentLocator.value
        notifyIsReady()
        val totalPages = publication.readingOrder.size
        val pageIndex = publication.readingOrder.indexOfFirstWithHref(initial.href) ?: 0
        visualListener.onPageChanged(pageIndex + 1, totalPages, initial)
    }

    override fun storeState(): Bundle =
        Bundle().apply {
            putString(
                currentVisualLocatorKey,
                currentVisualLocator?.toJSON()?.toString(),
            )
        }

    private var hasNotifiedIsReady = false

    private fun notifyIsReady() {
        if (hasNotifiedIsReady) return
        hasNotifiedIsReady = true
        visualListener.onVisualReaderIsReady()
    }

    // Navigator.Listener (inherited via ImageNavigatorFragment.Listener → VisualNavigator.Listener)

    override fun onJumpToLocator(locator: Locator) {
        PluginLog.d(TAG, "::onJumpToLocator $locator")
        notifyIsReady()
        val total = publication.readingOrder.size
        val pageIndex = publication.readingOrder.indexOfFirstWithHref(locator.href) ?: 0
        visualListener.onPageChanged(pageIndex + 1, total, locator)
        reapplyComicInsetsFix()
        launch {
            currentVisualLocator = locator
        }
    }

    // ImageNavigatorFragment does not emit external link events (no hyperlinks in comic pages).

    override fun onCurrentLocatorChanges(locator: Locator) {
        visualListener.onVisualCurrentLocationChanged(locator)
        reapplyComicInsetsFix()
    }

    override fun dispose() {
        super.dispose()
        launch {
            imageNavigator?.let { fragment ->
                fragment.parentFragmentManager.commitNow { remove(fragment) }
            }
            coroutineContext.cancelChildren()
            imageNavigator = null
        }
        state.clear()
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: EpubNavigator.VisualListener,
            state: Bundle,
        ): ComicNavigator {
            val locator =
                state
                    .getString(currentVisualLocatorKey)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            PluginLog.d(TAG, "::restoreState - locator: $locator")
            return ComicNavigator(publication, locator, listener)
        }
    }
}
