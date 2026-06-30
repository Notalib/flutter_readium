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
import java.lang.reflect.Proxy
import java.util.WeakHashMap
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "ComicNavigator"
private const val CURRENT_VISUAL_LOCATOR_KEY = "currentVisualLocator"

// At/below this PhotoView scale the page is considered "fit" (not zoomed), so horizontal
// swipes turn the page; above it, pan is locked into the viewer. See [configurePhotoViewPanLock].
private const val PAN_LOCK_FIT_SCALE = 1.05f

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
        get() = state[CURRENT_VISUAL_LOCATOR_KEY] as? Locator
        set(value) {
            state[CURRENT_VISUAL_LOCATOR_KEY] = value
        }

    private var imageNavigator: ImageNavigatorFragment? = null
    private var pagerInsetsListenerInstalled = false

    // PhotoViews already wired with the zoom-gated pan lock. WeakHashMap so ViewPager-recycled
    // page views don't pin and we don't reinstall the listener on every inset re-apply.
    private val panLockConfigured = WeakHashMap<View, Boolean>()

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

        if (view.javaClass.simpleName == "PhotoView") {
            configurePhotoViewPanLock(view)
            if (view.paddingTop != 0 ||
                view.paddingBottom != 0 ||
                view.paddingLeft != 0 ||
                view.paddingRight != 0
            ) {
                view.setPadding(0, 0, 0, 0)
            }
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

    /**
     * Locks manual pan inside a zoomed comic page so it isn't interpreted as a page swipe.
     *
     * WORKAROUND: [ImageNavigatorFragment] renders each page in a chrisbanes PhotoView inside an
     * R2ViewPager. With PhotoView's default `allowParentInterceptOnEdge = true`, panning a zoomed
     * page to its horizontal edge hands the gesture to the ViewPager and turns the page — so a
     * fast pan reads as a swipe. We gate that flag by zoom level via an OnMatrixChangeListener:
     * swipes still turn the page at fit ([PAN_LOCK_FIT_SCALE]), but are suppressed while zoomed so
     * the pan stays captured. The listener fires inside PhotoView's own drag handling before the
     * edge hand-off is evaluated, so the flag is current for each drag.
     *
     * PhotoView is a non-transitive (bundled-JAR) dependency of kotlin-toolkit, so there is no
     * compile-time type for it here — driven reflectively, like [clearComicInsets] above.
     * Best-effort: any reflection failure (e.g. upstream swaps the image view) is logged and
     * leaves the default paging behaviour intact.
     *
     * TODO(upstream): replace with a real flag once kotlin-toolkit exposes paging/zoom gesture
     *   coordination for ImageNavigatorFragment.
     */
    private fun configurePhotoViewPanLock(photoView: View) {
        if (panLockConfigured.containsKey(photoView)) return
        try {
            val cls = photoView.javaClass
            val getScale = cls.getMethod("getScale")
            val setAllowParentInterceptOnEdge =
                cls.getMethod("setAllowParentInterceptOnEdge", Boolean::class.javaPrimitiveType)
            val listenerCls =
                photoView.javaClass.classLoader
                    ?.loadClass("com.github.chrisbanes.photoview.OnMatrixChangedListener")
                    ?: return
            val setOnMatrixChangeListener = cls.getMethod("setOnMatrixChangeListener", listenerCls)

            val applyGate = {
                val scale = (getScale.invoke(photoView) as? Float) ?: 1f
                setAllowParentInterceptOnEdge.invoke(photoView, scale <= PAN_LOCK_FIT_SCALE)
            }

            val listener =
                Proxy.newProxyInstance(listenerCls.classLoader, arrayOf(listenerCls)) { proxy, method, args ->
                    when (method.name) {
                        "onMatrixChanged" -> {
                            applyGate()
                            null
                        }

                        "equals" -> {
                            proxy === args?.getOrNull(0)
                        }

                        "hashCode" -> {
                            System.identityHashCode(proxy)
                        }

                        "toString" -> {
                            "PhotoViewPanLockListener"
                        }

                        else -> {
                            null
                        }
                    }
                }
            setOnMatrixChangeListener.invoke(photoView, listener)
            applyGate() // Seed initial state (fit → paging enabled).
            panLockConfigured[photoView] = true
            PluginLog.d(TAG, "::configurePhotoViewPanLock - installed zoom-gated pan lock")
        } catch (e: Exception) {
            PluginLog.w(
                TAG,
                "::configurePhotoViewPanLock - failed (${e.message}); leaving default paging behaviour",
            )
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

    // --- Narration-sync catch-up (page-level) --------------------------------
    // Mirrors EpubNavigator's deferred-sync mechanism so a Re-sync after manual mode
    // jumps to the audio cue's PAGE immediately, matching iOS/Web. Panel-level framing
    // is Phase 2 — there is no panel pan/zoom API on Android yet (see
    // docs/parity/native-divina-sync-handoff.md). Segment duration is irrelevant to
    // comics (no per-word scroll), so unlike EpubNavigator only the locator is tracked.

    private var lastSyncLocator: Locator? = null

    /**
     * Navigates to an audio-cue locator and records it for catch-up. Only invoked when
     * narration sync is enabled — gating lives in [dk.nota.flutterreadium.ReadiumReader.syncVisualToLocator].
     */
    suspend fun syncToLocator(
        locator: Locator,
        animated: Boolean,
        segmentDuration: Double?,
    ) {
        lastSyncLocator = locator
        goToLocator(locator, animated, segmentDuration)
    }

    /**
     * Records the latest audio-cue locator without navigating, so a later
     * [resyncAfterManualMode] can jump to the current cue's page. Called while in manual mode.
     */
    fun recordDeferredSync(locator: Locator) {
        lastSyncLocator = locator
    }

    /**
     * Re-positions the comic to the last known audio-cue page after exiting manual mode.
     * Called by [dk.nota.flutterreadium.ReadiumReader.setNarrationSyncEnabled] when re-enabling sync.
     */
    suspend fun resyncAfterManualMode() {
        val locator =
            lastSyncLocator ?: run {
                PluginLog.d(TAG, "::resyncAfterManualMode - no lastSyncLocator stored")
                return
            }
        PluginLog.d(TAG, "::resyncAfterManualMode - catching up to page ${locator.href}")
        goToLocator(locator, animated = false, segmentDuration = null)
    }

    /**
     * Clears deferred-sync state when narration stops (not paused). Distinct from
     * [resyncAfterManualMode], which replays the last cue.
     */
    fun exitNarrationMode() {
        PluginLog.d(TAG, "::exitNarrationMode")
        lastSyncLocator = null
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
                CURRENT_VISUAL_LOCATOR_KEY,
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
                    .getString(CURRENT_VISUAL_LOCATOR_KEY)
                    ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            PluginLog.d(TAG, "::restoreState - locator: $locator")
            return ComicNavigator(publication, locator, listener)
        }
    }
}
