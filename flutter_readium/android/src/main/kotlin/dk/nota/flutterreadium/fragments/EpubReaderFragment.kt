package dk.nota.flutterreadium.fragments

import android.os.Bundle
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutterreadium.EpubImageTapBridge
import dk.nota.flutterreadium.FlutterEpubPreferences
import dk.nota.flutterreadium.NarrationSyncInterface
import dk.nota.flutterreadium.PluginLog
import dk.nota.flutterreadium.R
import dk.nota.flutterreadium.ReadiumReader
import dk.nota.flutterreadium.SpotlightStyle
import dk.nota.flutterreadium.effectiveForLayout
import dk.nota.flutterreadium.isFixed
import dk.nota.flutterreadium.models.EpubReaderViewModel
import dk.nota.flutterreadium.models.ViewPortSize
import dk.nota.flutterreadium.progression
import dk.nota.flutterreadium.requireOrLog
import dk.nota.flutterreadium.withMainContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.OverflowableNavigator
import org.readium.r2.navigator.SelectableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.css.FontStyle
import org.readium.r2.navigator.epub.css.FontWeight
import org.readium.r2.navigator.html.HtmlDecorationTemplate
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.KeyEvent
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.navigator.util.DirectionalNavigationAdapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "EpubReaderFragment"

private var instanceNo = 0

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class EpubReaderFragment :
    VisualReaderFragment(),
    EpubNavigatorFragment.Listener,
    EpubNavigatorFragment.PaginationListener {
    interface Listener {
        /**
         * Called when a page has finished loading.
         */
        fun onPageLoaded()

        /**
         * Called when the current page has changed.
         */
        fun onPageChanged(
            pageIndex: Int,
            totalPages: Int,
            locator: Locator,
        )

        /**
         * Called when an external link is activated.
         */
        fun onExternalLinkActivated(url: AbsoluteUrl)

        /**
         * Called for a native tap that content did not consume: [toggleControls] for a center tap,
         * otherwise an edge tap (whether or not the page turned).
         */
        fun onNativeTap(toggleControls: Boolean)
    }

    var listener: Listener? = null

    val started = MutableStateFlow(false)

    /** True after the current child navigator has loaded its first visible page. */
    val pageLoaded = MutableStateFlow(false)

    val scrollMode: Boolean
        get() = epubNavigator?.settings?.value?.scroll == true

    val layoutMode: Layout
        get() =
            ReadiumReader.currentPublication
                ?.metadata
                ?.layout
                ?: Layout.REFLOWABLE

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

    override fun onPageChanged(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        PluginLog.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.progression}",
        )

        cacheReflowablePage(pageIndex, totalPages, locator)
        listener?.onPageChanged(pageIndex, totalPages, locator)
    }

    /** Last reported page, in reading order: the position of its resource and its logical page. */
    private class ReflowablePage(
        val readingOrderPosition: Int,
        val pageIndex: Int,
        val totalPages: Int,
    )

    private var reflowablePage: ReflowablePage? = null

    // The toolkit reports the physical page, which is mirrored in RTL.
    private fun cacheReflowablePage(
        pageIndex: Int,
        totalPages: Int,
        locator: Locator,
    ) {
        val rtl = epubNavigator?.overflow?.value?.readingProgression == ReadingProgression.RTL
        val position =
            ReadiumReader.currentPublication?.readingOrder?.indexOfFirst {
                it.href.resolve().isEquivalent(locator.href)
            }
        reflowablePage =
            if (position == null || position < 0) {
                null
            } else {
                ReflowablePage(position, logicalPageIndex(pageIndex, totalPages, rtl), totalPages)
            }
    }

    // The cache is cleared on any change it cannot follow, so a stale page never blocks a turn.
    override fun go(
        locator: Locator?,
        animated: Boolean,
    ): Boolean {
        reflowablePage = null
        return super.go(locator, animated)
    }

    /**
     * The toolkit's reflowable turns return true once queued (acceptance, not movement), even at the
     * publication ends. This rejects that no-op from the last reported page; unknown state never does.
     */
    private fun turnUnlessAtBoundary(
        forward: Boolean,
        turn: () -> Boolean,
    ): Boolean {
        val page = reflowablePage
        val readingOrderSize = ReadiumReader.currentPublication?.readingOrder?.size
        if (page != null && readingOrderSize != null &&
            isAtPublicationBoundary(forward, page.readingOrderPosition, readingOrderSize, page.pageIndex, page.totalPages)
        ) {
            return false
        }
        return turn().also { if (it) reflowablePage = null }
    }

    override fun onPageLoaded() {
        PluginLog.d(TAG, "::onPageLoaded")
        pageLoaded.value = true
        lifecycleScope.launch {
            applyCustomCssVariables()
            injectImageTapListeners()
        }
        listener?.onPageLoaded()
    }

    private suspend fun injectImageTapListeners() {
        evaluateJavascript(
            """
            (function() {
                if (window.__flutterImageBridgeReady) return;
                if (typeof FlutterImageBridge === 'undefined') return;
                window.__flutterImageBridgeReady = true;
                document.addEventListener('click', function(e) {
                    var img = e.target && e.target.closest ? e.target.closest('img') : null;
                    if (!img) return;
                    var figure = img.closest ? img.closest('figure') : null;
                    var comicContainer = img.closest ? img.closest('.nota-comicbook-page-container') : null;
                    var r = img.getBoundingClientRect();
                    FlutterImageBridge.onImageTapped(JSON.stringify({
                        srcUrl: img.src || '',
                        alt: img.getAttribute('alt') || null,
                        notaComicPageImage: !!((img.classList && img.classList.contains('page') && figure && figure.querySelector('.area')) || comicContainer),
                        rect: { x: r.left, y: r.top, width: r.width, height: r.height },
                        nw: img.naturalWidth || 0,
                        nh: img.naturalHeight || 0
                    }));
                }, true);
            })();
            """.trimIndent(),
        )
    }

    private fun readingOrderPositionOrLog(
        publication: Publication,
        locator: Locator,
    ): Int? {
        val position =
            publication.readingOrder.indexOfFirst {
                it.href.resolve().isEquivalent(locator.href)
            }
        if (position < 0) {
            PluginLog.e(
                TAG,
                "::readingOrderPositionOrLog - current reading order item not from {${locator.href}}",
            )
            return null
        }
        return position
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return null

        return withMainContext {
            navigator.firstVisibleElementLocator()
        }
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return

        return withMainContext {
            navigator.applyDecorations(decorations, group)
        }
    }

    fun addDecorationListener(
        group: String,
        listener: org.readium.r2.navigator.DecorableNavigator.Listener,
    ) {
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return
        navigator.addDecorationListener(group, listener)
    }

    /**
     * Evaluate JavaScript in the context of the navigator's WebView.
     * NOTE: Returns null on error and if script returns null/undefined.
     */
    suspend fun evaluateJavascript(script: String): String? {
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return null

        return withMainContext {
            return@withMainContext navigator.evaluateJavascript(script)
        }
    }

    /**
     * Update the reader preferences.
     */
    suspend fun updatePreferences(preferences: FlutterEpubPreferences) {
        val model =
            requireOrLog(TAG, epubVm, "No epubVm available.") ?: return

        model.preferences = preferences
        // Preferences can change the layout and direction until the next page callback.
        reflowablePage = null

        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return

        return withMainContext {
            PluginLog.d(TAG, "::updatePreferences: $preferences")

            applyCustomCssVariables()
            navigator.submitPreferences(preferences.toEpubPreferences())
        }
    }

    suspend fun applyCustomCssVariables() {
        val model =
            requireOrLog(TAG, epubVm, "No epubVm available.") ?: return

        PluginLog.d(TAG, "::applyCustomCssVariables - layoutMode:$layoutMode")

        val cssVariables =
            model.preferences?.effectiveForLayout(layoutMode)?.toCustomCssVariables() ?: run {
                PluginLog.d(TAG, "::applyCustomCssVariables - no css variables")
                return
            }

        PluginLog.d(TAG, "::applyCustomCssVariables - update cssVariables:$cssVariables")

        evaluateJavascript("readium.setCSSProperties(${JSONObject(cssVariables)});")
    }

    /**
     * Navigate backward. Readium component handles RTL / LTR
     */
    suspend fun goBackward(animated: Boolean): Boolean {
        PluginLog.d(TAG, "::goBackward")
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return false

        if (layoutMode.isFixed) {
            PluginLog.d(TAG, "::goBackward - fixed layout mode")
            return goBackwardFixed(animated)
        }

        if (!layoutMode.isFixed && scrollMode) {
            return goBackwardVertical(animated)
        }

        return withMainContext {
            val moved = turnUnlessAtBoundary(forward = false) { navigator.goBackward(animated) }
            PluginLog.d(TAG, if (moved) "::goBackward: Went back." else "::goBackward: Couldn't go back.")
            moved
        }
    }

    /**
     * Go backward one reading-order item in fixed-layout mode.
     */
    private suspend fun goBackwardFixed(animated: Boolean): Boolean =
        goFixedByReadingOrderOffset(
            offset = -1,
            animated = animated,
            boundaryMessage = "reached the beginning.",
            successMessage = "Went back to",
            failureMessage = "Couldn't go back to",
        )

    /**
     * Go backwards in vertical scroll mode.
     */
    private suspend fun goBackwardVertical(animated: Boolean): Boolean {
        if (layoutMode.isFixed || !scrollMode) {
            PluginLog.e(TAG, "::goBackwardVertical - this is only meant for vertical scroll mode")
        }

        val locator =
            requireOrLog(TAG, currentLocator?.value, "No current locator.") ?: return false

        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return false

        val viewPortSize =
            requireOrLog(TAG, currentViewPortSize(), "Failed to load view port size.") ?: return false

        val publication =
            requireOrLog(TAG, ReadiumReader.currentPublication, "No current publication.") ?: return false

        val prevProgression = viewPortSize.prevProgression
        if (viewPortSize.progression <= 0.0 && prevProgression <= 0.0) {
            val position = readingOrderPositionOrLog(publication, locator) ?: return false

            // Current progress is already at the top and prevProgression is <= 0.0,
            // We need to go to the previous file in the readingOrder.
            val prevPosition = position - 1
            if (prevPosition < 0) {
                // Reached the beginning
                PluginLog.d(TAG, "::goBackwardVertical - reached the beginning.")
                return false
            }

            PluginLog.d(TAG, "::goBackwardVertical go to previous chapter, progression:$prevProgression")
            val prevLink =
                requireOrLog(TAG, publication.readingOrder.getOrNull(prevPosition), "Reached the beginning.") ?: return false
            val prevLocator =
                requireOrLog(
                    TAG,
                    publication.locatorFromLink(prevLink)?.copyWithLocations(
                        progression = 1.0,
                        totalProgression = null,
                    ),
                    "Failed to make locator from link.",
                ) ?: return false

            return withMainContext {
                navigator.go(prevLocator, animated)
            }
        }

        scrollToProgression(prevProgression)
        return true
    }

    /**
     * Navigate forward. Readium component handles RTL / LTR
     */
    @OptIn(InternalReadiumApi::class)
    suspend fun goForward(animated: Boolean): Boolean {
        PluginLog.d(TAG, "::goForward")
        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return false

        if (!layoutMode.isFixed && scrollMode) {
            return goForwardVertical(animated)
        }

        if (layoutMode.isFixed) {
            PluginLog.d(TAG, "::goForward - fixed layout mode")
            return goForwardFixed(animated)
        }

        return withMainContext {
            val moved = turnUnlessAtBoundary(forward = true) { navigator.goForward(animated) }
            PluginLog.d(TAG, if (moved) "::goForward: Went forward." else "::goForward: Couldn't go forward.")
            moved
        }
    }

    /**
     * Go forward one reading-order item in fixed-layout mode.
     */
    private suspend fun goForwardFixed(animated: Boolean): Boolean =
        goFixedByReadingOrderOffset(
            offset = 1,
            animated = animated,
            boundaryMessage = "reached end.",
            successMessage = "Went forward to",
            failureMessage = "Couldn't go forward to",
        )

    /**
     * Go one reading-order item forward or backward in fixed-layout mode.
     */
    private suspend fun goFixedByReadingOrderOffset(
        offset: Int,
        animated: Boolean,
        boundaryMessage: String,
        successMessage: String,
        failureMessage: String,
    ): Boolean {
        val locator =
            requireOrLog(TAG, currentLocator?.value, "No current locator.") ?: return false
        PluginLog.d(TAG, "::goFixedByReadingOrderOffset - current locator: $locator")

        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return false

        val publication =
            requireOrLog(TAG, ReadiumReader.currentPublication, "No current publication.") ?: return false

        val position = readingOrderPositionOrLog(publication, locator) ?: return false
        PluginLog.d(
            TAG,
            "::goFixedByReadingOrderOffset - resolved reading-order position: $position of ${publication.readingOrder.size}",
        )

        val targetLink =
            requireOrLog(TAG, publication.readingOrder.getOrNull(position + offset), boundaryMessage) ?: return false

        val targetLocator =
            requireOrLog(TAG, publication.locatorFromLink(targetLink), "Failed to make locator from link.") ?: return false
        PluginLog.d(TAG, "::goFixedByReadingOrderOffset - target link: ${targetLink.href}")
        PluginLog.d(TAG, "::goFixedByReadingOrderOffset - target locator: $targetLocator")

        return withMainContext {
            val moved = navigator.go(targetLocator, animated)
            PluginLog.d(TAG, "::goFixedByReadingOrderOffset - navigator.go returned $moved")
            if (moved) {
                PluginLog.d(TAG, "::goFixedByReadingOrderOffset - $successMessage ${targetLink.href}.")
            } else {
                PluginLog.d(TAG, "::goFixedByReadingOrderOffset - $failureMessage ${targetLink.href}.")
            }
            moved
        }
    }

    /**
     * Go forward in vertical scroll mode
     */
    private suspend fun goForwardVertical(animated: Boolean): Boolean {
        if (layoutMode.isFixed || !scrollMode) {
            PluginLog.e(TAG, "::goForwardVertical - this is only meant for vertical scroll mode")
        }

        val locator =
            requireOrLog(TAG, currentLocator?.value, "No current locator.") ?: return false

        val navigator =
            requireOrLog(TAG, epubNavigator, "Navigator not ready.") ?: return false

        val viewPortSize =
            requireOrLog(TAG, currentViewPortSize(), "Failed to load view port size.") ?: return false

        val publication =
            requireOrLog(TAG, ReadiumReader.currentPublication, "No current publication.") ?: return false

        val endProgression = viewPortSize.endProgression
        val nextProgression = viewPortSize.nextProgression

        if (nextProgression >= 1.0 && endProgression >= 1.0) {
            val position = readingOrderPositionOrLog(publication, locator) ?: return false

            // Attempted to over the end of the current file.
            val nextPosition = position + 1
            if (nextPosition >= publication.readingOrder.size) {
                PluginLog.d(TAG, "::goForwardVertical - reached end.")
                return false
            }

            PluginLog.d(TAG, "::goForwardVertical. load next chapter, progression:$nextProgression")
            val nextLink =
                requireOrLog(TAG, publication.readingOrder.getOrNull(nextPosition), "Reached end.") ?: return false
            return withMainContext { navigator.go(nextLink, animated) }
        }

        scrollToProgression(nextProgression)
        return true
    }

    /**
     * Get current view port size information.
     */
    suspend fun currentViewPortSize(): ViewPortSize? {
        try {
            val viewPortSize =
                ViewPortSize.fromJson(
                    evaluateJavascript("window.flutterReadium.getViewPortSize()") ?: "",
                    scrollMode,
                )
            return viewPortSize
        } catch (_: Exception) {
            return null
        } catch (_: Error) {
            return null
        }
    }

    /**
     * Scroll to progression, coerce to >=0.0 and <=1.0
     */
    suspend fun scrollToProgression(progression: Double) {
        val coercedProgression = progression.coerceIn(0.0, 1.0)
        PluginLog.d(TAG, "::scrollToProgression - scroll to progression - $coercedProgression")
        evaluateJavascript("readium.scrollToPosition($coercedProgression)")
    }

    /**
     * Android lifecycle resume method, reattaches the navigator if needed.
     */
    override fun onResume() {
        try {
            PluginLog.d(TAG, "::onResume - $instance - $attachingNavigatorFragment")

            if (epubVm == null) {
                PluginLog.d(TAG, "::onResume - $instance - missing view model")
                return
            }

            if (attachingNavigatorFragment) {
                PluginLog.d(TAG, "::onResume - $instance - don't attach navigator")
                return
            }

            // Recreate/attach the navigator after soft suspend.
            attachNavigator()
        } finally {
            super.onResume()
            PluginLog.d(TAG, "::onResume - $instance - ended")
        }
    }

    /**
     * Android lifecycle view created method, creates and attaches the navigator.
     */
    override fun onViewCreated(
        view: View,
        savedInstanceState: Bundle?,
    ) {
        try {
            super.onViewCreated(view, savedInstanceState)

            PluginLog.d(TAG, "::onViewCreated - $instance $view, $savedInstanceState")

            val model = epubVm
            if (model == null) {
                PluginLog.d(TAG, "::onViewCreated - $instance - missing reader data")
                return
            }

            // Prevent onResume from attempting to add the navigator while we work.
            attachingNavigatorFragment = true

            lifecycleScope.launch {
                if (ReadiumReader.currentPublication != null) {
                    PluginLog.d(TAG, "::onViewCreated - $instance - attach navigator")
                    attachNavigator()
                } else {
                    PluginLog.d(TAG, "::onViewCreated - $instance - publication is missing")
                }

                attachingNavigatorFragment = false
            }
        } finally {
            PluginLog.d(TAG, "::onViewCreated - $instance - ended")
        }
    }

    /**
     * Android lifecycle pause method, detaches the navigator to save resources and prevent caches.
     */
    override fun onPause() {
        try {
            PluginLog.d(TAG, "::onPause - $instance")

            epubVm?.locator = currentLocator?.value

            epubNavigator?.let { fragment ->
                childFragmentManager.commitNow {
                    remove(fragment)
                }
            }

            epubNavigator = null
            reflowablePage = null
            started.value = false
            pageLoaded.value = false

            attachingNavigatorFragment = false

            super.onPause()
        } finally {
            PluginLog.d(TAG, "::onPause - $instance - ended")
        }
    }

    private var attachingNavigatorFragment = false

    private fun pagedTurn(
        forward: Boolean,
        turn: () -> Boolean,
    ) = if (layoutMode.isFixed || scrollMode) turn() else turnUnlessAtBoundary(forward, turn)

    /**
     * Wraps the stock [DirectionalNavigationAdapter] so zones, RTL and keys stay upstream. The
     * wrapped navigator records whether a turn was attempted, so a failed edge turn is not a center tap.
     */
    private fun createNativeInputListener(navigator: OverflowableNavigator): InputListener {
        var turnAttempted = false
        val recordingNavigator =
            object : OverflowableNavigator by navigator {
                override fun goForward(animated: Boolean): Boolean {
                    turnAttempted = true
                    return pagedTurn(forward = true) { navigator.goForward(animated) }
                }

                override fun goBackward(animated: Boolean): Boolean {
                    turnAttempted = true
                    return pagedTurn(forward = false) { navigator.goBackward(animated) }
                }
            }
        val adapter = DirectionalNavigationAdapter(recordingNavigator)

        return object : InputListener {
            override fun onTap(event: TapEvent): Boolean {
                turnAttempted = false
                val turned = adapter.onTap(event)
                if (turned) {
                    ReadiumReader.enterManualModeIfNarrating("onTap")
                }
                listener?.onNativeTap(toggleControls = !turnAttempted)
                return turned
            }

            override fun onKey(event: KeyEvent): Boolean {
                val consumed = adapter.onKey(event)
                if (consumed) {
                    ReadiumReader.enterManualModeIfNarrating("onKey")
                }
                return consumed
            }
        }
    }

    /**
     * Attach the navigator fragment to this reader fragment.
     */
    private fun attachNavigator() {
        PluginLog.d(TAG, "::attachNavigator() - $instance")
        if (navigator != null) {
            PluginLog.d(TAG, "::attachNavigator() - $instance - already attached")
            return
        }

        val model = epubVm
        if (model == null) {
            PluginLog.w(TAG, "::attachNavigator() - $instance - missing view model")
            return
        }

        if (ReadiumReader.currentPublication == null) {
            PluginLog.w(TAG, "::attachNavigator() - $instance - missing publication")
            return
        }

        val preferences = model.preferences ?: FlutterEpubPreferences()
        model.preferences = preferences
        val navigatorFactory = model.navigatorFactory!!

        val navigatorConfig =
            EpubNavigatorFragment
                .Configuration(
                    disablePageTurnsWhileScrolling = model.disablePageTurnsWhileScrolling,
                    // Padding should be added on Flutter side
                    shouldApplyInsetsPadding = false,
                    // Extra served asssets will be relative to your app's src/main/assets/ folder.
                    // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
                    // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
                    servedAssets =
                        listOf("flutter_assets/packages/flutter_readium/assets/.*") +
                            model.fontFamilyDeclarations.flatMap { family ->
                                family.faces.map { face -> face.asset }
                            },
                    // Use experimentalPositioning in decoration templates. It places highlights behind text, instead of on top.
                    decorationTemplates =
                        HtmlDecorationTemplates
                            .defaultTemplates(
                                alpha = 1.0,
                                experimentalPositioning = true,
                            ).also { templates ->
                                templates[SpotlightStyle::class] = spotlightDecorationTemplate()
                            },
                    // Only register the callback if custom selectionActions are added.
                    selectionActionModeCallback =
                        if (ReadiumReader.selectionActions.isNotEmpty()) {
                            createSelectionActionModeCallback()
                        } else {
                            null
                        },
                ).apply {
                    model.fontFamilyDeclarations.forEach { family ->
                        addFontFamilyDeclaration(
                            FontFamily(family.name),
                            family.fallbacks.map(::FontFamily),
                        ) {
                            family.faces.forEach { face ->
                                addFontFace {
                                    addSource(face.asset)
                                    setFontStyle(
                                        when (face.style) {
                                            dk.nota.flutterreadium.ReaderFontStyle.NORMAL -> FontStyle.NORMAL
                                            dk.nota.flutterreadium.ReaderFontStyle.ITALIC -> FontStyle.ITALIC
                                        },
                                    )
                                    FontWeight.entries
                                        .firstOrNull { it.value == face.weight }
                                        ?.let(::setFontWeight)
                                        ?: setFontWeight(face.weight..face.weight)
                                }
                            }
                        }
                    }

                    // Register JS→native bridge for window.updateNarrationSync(bool).
                    registerJavascriptInterface(NarrationSyncInterface.JS_NAME) { _ -> NarrationSyncInterface(ReadiumReader) }

                    // TODO: This is a temporary solution until kotlin-toolkit supports image tap events natively.
                    // Register JS→native bridge for window.onImageTappedCallback(string).
                    registerJavascriptInterface("FlutterImageBridge") { _ -> EpubImageTapBridge() }
                }

        val fragmentFactory =
            navigatorFactory.createFragmentFactory(
                configuration = navigatorConfig,
                initialLocator = model.locator,
                listener = this,
                paginationListener = this,
                initialPreferences = preferences.toEpubPreferences(),
            )

        val epubNavigator =
            fragmentFactory.instantiate(
                requireActivity().classLoader,
                EpubNavigatorFragment::class.java.name,
            ) as EpubNavigatorFragment

        PluginLog.d(TAG, "::attachNavigator() - $instance - add fragment")
        childFragmentManager.commitNow {
            add(
                R.id.fragment_reader_container,
                epubNavigator,
                NAVIGATOR_FRAGMENT_TAG,
            )
        }

        (epubNavigator as OverflowableNavigator).apply {
            // Turns pages when tapping the screen edges or pressing arrow keys.
            addInputListener(createNativeInputListener(this))
        }

        navigator = epubNavigator
        PluginLog.d(TAG, "::attachNavigator() - $instance - got navigator = $navigator")

        started.value = true
    }

    /**
     * Creates an ActionMode.Callback that fires onTextSelected and onSelectionAction.
     * Only registered when selectionActions is non-empty — when null is passed instead,
     * Readium uses the WebView's default callback which shows system Copy/Share/SelectAll.
     *
     * Note: providing a custom selectionActionModeCallback to Readium fully replaces the
     * WebView's default ActionMode.Callback, so system items are not shown. Do NOT try to
     * re-add them manually — see AGENTS.md "Prefer honest limitations over brittle workarounds".
     */
    private fun createSelectionActionModeCallback(): ActionMode.Callback {
        // Menu item IDs start at this offset to avoid collisions with system items.
        val menuItemIdOffset = 100

        return object : ActionMode.Callback {
            override fun onCreateActionMode(
                mode: ActionMode?,
                menu: Menu?,
            ): Boolean {
                PluginLog.d(TAG, "::onCreateActionMode - text selection detected")
                // Fire onTextSelected callback.
                lifecycleScope.launch {
                    val nav = navigator as? SelectableNavigator ?: return@launch
                    val selection = nav.currentSelection() ?: return@launch
                    val channel = ReadiumReader.currentReaderWidget?.channel ?: return@launch
                    channel.onTextSelected(
                        selection.locator,
                        selection.locator.text.highlight,
                    )
                }
                return true
            }

            override fun onPrepareActionMode(
                mode: ActionMode?,
                menu: Menu?,
            ): Boolean {
                if (menu == null) return false
                var changed = false

                // Add configured custom actions to the menu.
                val actions = ReadiumReader.selectionActions
                actions.forEachIndexed { index, action ->
                    if (menu.findItem(menuItemIdOffset + index) == null) {
                        menu.add(Menu.NONE, menuItemIdOffset + index, Menu.NONE, action.title)
                        changed = true
                    }
                }
                return changed
            }

            override fun onActionItemClicked(
                mode: ActionMode?,
                item: MenuItem?,
            ): Boolean {
                if (item == null) return false
                val index = item.itemId - menuItemIdOffset
                val actions = ReadiumReader.selectionActions
                if (index < 0 || index >= actions.size) return false

                val action = actions[index]
                PluginLog.d(TAG, "::onActionItemClicked - action: ${action.id}")

                lifecycleScope.launch {
                    val nav = navigator as? SelectableNavigator ?: return@launch
                    val selection = nav.currentSelection() ?: return@launch
                    val channel = ReadiumReader.currentReaderWidget?.channel ?: return@launch
                    channel.onSelectionAction(
                        action.id,
                        selection.locator,
                        selection.locator.text.highlight,
                    )
                }

                mode?.finish()
                return true
            }

            override fun onDestroyActionMode(mode: ActionMode?) {
                // No-op
            }
        }
    }

    companion object {
        private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_EPUB_READER_FRAGMENT"

        /**
         * Spotlight: semi-transparent tinted box over the active range, one per text line.
         *
         * Uses BOXES layout (one element per CSS border box / text line) so that utterances
         * spanning CSS columns are represented by per-line boxes each contained within their
         * own column. BOUNDS would produce a single rectangle spanning the bounding box of
         * the whole range, which overflows across the gutter and into the next column when
         * an utterance crosses a column boundary.
         *
         * The class `flutter-readium-spotlight` is a stable marker that
         * `flutterReadiumTools.js` watches via MutationObserver to:
         *   1. Toggle `body.flutter-readium-spotlight-active`, which fades all body text
         *      to low contrast via an injected CSS rule.
         *   2. Read `data-css-selector` and add `.flutter-readium-spotlit-text` to the
         *      matching element, so a higher-specificity CSS rule restores its text colour.
         *
         * `background-color` MUST be `!important`: Readium CSS forces every element's
         * background to transparent when a custom theme is active (see Gotcha in AGENTS.md);
         * without `!important` the fill would be invisible.
         *
         * `z-index: -1` renders the fill behind the text glyphs (same as the upstream
         * highlight/underline templates). This keeps the text colour visually
         * unaffected by the tint overlay and matches what `::highlight()` does on web —
         * the yellow acts purely as a background, not a colour wash.
         */
        private fun spotlightDecorationTemplate(): HtmlDecorationTemplate =
            HtmlDecorationTemplate(
                layout = HtmlDecorationTemplate.Layout.BOXES,
                width = HtmlDecorationTemplate.Width.BOUNDS,
                element = { decoration ->
                    val tint = (decoration.style as? SpotlightStyle)?.tint ?: android.graphics.Color.TRANSPARENT
                    val bgColor =
                        if (android.graphics.Color.alpha(tint) == 0) {
                            "transparent"
                        } else {
                            val r = android.graphics.Color.red(tint)
                            val g = android.graphics.Color.green(tint)
                            val b = android.graphics.Color.blue(tint)
                            "rgba($r,$g,$b,0.5)"
                        }

                    fun String.escAttr() =
                        replace("&", "&amp;")
                            .replace("\"", "&quot;")
                            .replace("<", "&lt;")
                            .replace(">", "&gt;")
                    val sel = (decoration.locator.locations.cssSelector ?: "").escAttr()
                    val hl = (decoration.locator.text.highlight ?: "").escAttr()
                    val bef = (decoration.locator.text.before ?: "").escAttr()
                    """<div class="flutter-readium-spotlight" data-css-selector="$sel" data-text-highlight="$hl" data-text-before="$bef" data-tint="$bgColor" style="z-index: -1; box-sizing: border-box;"/>"""
                },
            )
    }
}

/** Mirrors the toolkit's physical page index to the logical one for RTL. */
internal fun logicalPageIndex(
    physicalIndex: Int,
    totalPages: Int,
    rtl: Boolean,
): Int = if (rtl && totalPages > 0) totalPages - 1 - physicalIndex else physicalIndex

/** True when a turn in [forward] direction from this page has nowhere to go in the publication. */
internal fun isAtPublicationBoundary(
    forward: Boolean,
    readingOrderPosition: Int,
    readingOrderSize: Int,
    pageIndex: Int,
    totalPages: Int,
): Boolean {
    if (totalPages <= 0) return false
    return if (forward) {
        readingOrderPosition == readingOrderSize - 1 && pageIndex >= totalPages - 1
    } else {
        readingOrderPosition == 0 && pageIndex <= 0
    }
}
