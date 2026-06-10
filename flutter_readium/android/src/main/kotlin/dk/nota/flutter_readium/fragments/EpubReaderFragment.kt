package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.FlutterEpubPreferences
import dk.nota.flutter_readium.PluginLog
import dk.nota.flutter_readium.R
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.SpotlightStyle
import dk.nota.flutter_readium.isFixed
import dk.nota.flutter_readium.models.EpubReaderViewModel
import dk.nota.flutter_readium.models.ViewPortSize
import dk.nota.flutter_readium.progression
import dk.nota.flutter_readium.withMainContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.OverflowableNavigator
import org.readium.r2.navigator.SelectableNavigator
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.html.HtmlDecorationTemplate
import org.readium.r2.navigator.html.HtmlDecorationTemplates
import org.readium.r2.navigator.util.DirectionalNavigationAdapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Layout
import org.readium.r2.shared.publication.Locator
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
    }

    var listener: Listener? = null

    val started = MutableStateFlow(false)

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

        listener?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onPageLoaded() {
        PluginLog.d(TAG, "::onPageLoaded")
        lifecycleScope.launch {
            applyCustomCssVariables()
        }
        listener?.onPageLoaded()
    }

    suspend fun firstVisibleElementLocator(): Locator? {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::firstVisibleElementLocator. Navigator not ready.")
                return null
            }

        return withMainContext {
            navigator.firstVisibleElementLocator()
        }
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>,
        group: String,
    ) {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::applyDecorations. Navigator not ready.")
                return
            }

        return withMainContext {
            navigator.applyDecorations(decorations, group)
        }
    }

    fun addDecorationListener(
        group: String,
        listener: org.readium.r2.navigator.DecorableNavigator.Listener,
    ) {
        val navigator =
            epubNavigator ?: run {
                PluginLog.w(TAG, "::addDecorationListener. Navigator not ready.")
                return
            }
        navigator.addDecorationListener(group, listener)
    }

    /**
     * Evaluate JavaScript in the context of the navigator's WebView.
     * NOTE: Returns null on error and if script returns null/undefined.
     */
    suspend fun evaluateJavascript(script: String): String? {
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::evaluateJavascript. Navigator not ready.")
                return null
            }

        return withMainContext {
            return@withMainContext navigator.evaluateJavascript(script)
        }
    }

    /**
     * Update the reader preferences.
     */
    suspend fun updatePreferences(preferences: FlutterEpubPreferences) {
        val model =
            epubVm ?: run {
                PluginLog.w(TAG, "::updatePreferences - No epubVm available, how did this happen?")
                return
            }

        model.preferences = preferences

        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::updatePreferences. Navigator not ready.")
                return
            }

        return withMainContext {
            PluginLog.d(TAG, "::updatePreferences: $preferences")

            applyCustomCssVariables()
            navigator.submitPreferences(preferences.toEpubPreferences())
        }
    }

    suspend fun applyCustomCssVariables() {
        val model =
            epubVm ?: run {
                PluginLog.w(TAG, "::applyCustomCssVariables - No epubVm available, how did this happen?")
                return
            }

        val cssVariables =
            model.preferences?.toCustomCssVariables() ?: run {
                PluginLog.d(TAG, "::applyCustomCssVariables - no css variables")
                return
            }

        PluginLog.d(TAG, "::applyCustomCssVariables - update cssVariables:$cssVariables")

        evaluateJavascript("readium.setCSSProperties(${JSONObject(cssVariables)});")
    }

    /**
     * Navigate backward. Readium component handles RTL / LTR
     */
    suspend fun goBackward(animated: Boolean) {
        PluginLog.d(TAG, "::goBackward")
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::goBackward. Navigator not ready.")
                return
            }

        if (!layoutMode.isFixed && scrollMode) {
            goBackwardVertical(animated)
            return
        }

        return withMainContext {
            if (navigator.goBackward(animated)) {
                PluginLog.d(TAG, "::goBackward: Went back.")
            } else {
                PluginLog.d(TAG, "::goBackward: Couldn't go back.")
            }
        }
    }

    /**
     * Go backwards in vertical scroll mode.
     */
    private suspend fun goBackwardVertical(animated: Boolean) {
        if (layoutMode.isFixed || !scrollMode) {
            PluginLog.e(TAG, "::goBackwardVertical - this is only meant for vertical scroll mode")
        }

        val locator =
            currentLocator?.value ?: run {
                PluginLog.e(TAG, "::goBackwardVertical - no current locator")
                return
            }

        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::goBackwardVertical. Navigator not ready.")
                return
            }

        val viewPortSize =
            currentViewPortSize() ?: run {
                PluginLog.e(TAG, "::goBackwardVertical - failed to load view port size")
                return
            }

        val publication =
            ReadiumReader.currentPublication ?: run {
                PluginLog.e(TAG, "::goBackwardVertical - no current publication?")
                return
            }

        val prevProgression = viewPortSize.prevProgression
        if (viewPortSize.progression <= 0.0 && prevProgression <= 0.0) {
            val position =
                publication.readingOrder.indexOfFirst {
                    it.href.resolve().isEquivalent(locator.href)
                }

            if (position < 0) {
                PluginLog.e(
                    TAG,
                    "::goBackwardVertical - current reading order item not from {${locator.href}}",
                )
                return
            }

            // Current progress is already at the top and prevProgression is <= 0.0,
            // We need to go to the previous file in the readingOrder.
            val prevPosition = position - 1
            if (prevPosition < 0) {
                // Reached the beginning
                PluginLog.d(TAG, "::goBackwardVertical - reached the beginning.")
                return
            }

            PluginLog.d(TAG, "::goBackwardVertical go to previous chapter, progression:$prevProgression")
            val prevLink =
                publication.readingOrder.getOrNull(prevPosition) ?: run {
                    PluginLog.d(TAG, "::goBackwardVertical - reached the beginning.")
                    return
                }
            val prevLocator =
                publication.locatorFromLink(prevLink)?.copyWithLocations(
                    progression = 1.0,
                    totalProgression = null,
                ) ?: run {
                    PluginLog.d(TAG, "::goBackwardVertical - failed to make locator from link")
                    return
                }

            return withMainContext {
                navigator.go(prevLocator, animated)
            }
        }

        scrollToProgression(prevProgression)
    }

    /**
     * Navigate forward. Readium component handles RTL / LTR
     */
    @OptIn(InternalReadiumApi::class)
    suspend fun goForward(animated: Boolean) {
        PluginLog.d(TAG, "::goForward")
        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::goForward. Navigator not ready.")
                return
            }

        if (!layoutMode.isFixed && scrollMode) {
            goForwardVertical(animated)
            return
        }

        return withMainContext {
            if (navigator.goForward(animated)) {
                PluginLog.d(TAG, "::goForward: Went forward.")
            } else {
                PluginLog.d(TAG, "::goForward: Couldn't go forward.")
            }
        }
    }

    /**
     * Go forward in vertical scroll mode
     */
    private suspend fun goForwardVertical(animated: Boolean) {
        if (layoutMode.isFixed || !scrollMode) {
            PluginLog.e(TAG, "::goForwardVertical - this is only meant for vertical scroll mode")
        }

        val locator =
            currentLocator?.value ?: run {
                PluginLog.e(TAG, "::goForwardVertical - no current locator")
                return
            }

        val navigator =
            epubNavigator ?: run {
                PluginLog.d(TAG, "::goForwardVertical. Navigator not ready.")
                return
            }

        val viewPortSize =
            currentViewPortSize() ?: run {
                PluginLog.e(TAG, "::goForwardVertical - failed to load view port size")
                return
            }

        val publication =
            ReadiumReader.currentPublication ?: run {
                PluginLog.e(TAG, "::goForwardVertical - no current publication?")
                return
            }

        val endProgression = viewPortSize.endProgression
        val nextProgression = viewPortSize.nextProgression

        if (nextProgression >= 1.0 && endProgression >= 1.0) {
            val position =
                publication.readingOrder.indexOfFirst {
                    it.href.resolve().isEquivalent(locator.href)
                }

            if (position < 0) {
                PluginLog.e(
                    TAG,
                    "::goForwardVertical - current reading order item not from {${locator.href}}",
                )
                return
            }

            // Attempted to over the end of the current file.
            val nextPosition = position + 1
            if (nextPosition >= publication.readingOrder.size) {
                PluginLog.d(TAG, "::goForwardVertical - reached end.")
                return
            }

            PluginLog.d(TAG, "::goForwardVertical. load next chapter, progression:$nextProgression")
            val nextLink =
                publication.readingOrder.getOrNull(nextPosition) ?: run {
                    PluginLog.d(TAG, "::goForwardVertical - reached end.")
                    return
                }
            return withMainContext { navigator.go(nextLink, animated) }
        }

        scrollToProgression(nextProgression)
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
            started.value = false

            attachingNavigatorFragment = false

            super.onPause()
        } finally {
            PluginLog.d(TAG, "::onPause - $instance - ended")
        }
    }

    private var attachingNavigatorFragment = false

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

        val fragmentFactory =
            navigatorFactory.createFragmentFactory(
                configuration =
                    EpubNavigatorFragment.Configuration(
                        // Padding should be added on Flutter side
                        shouldApplyInsetsPadding = false,
                        // Extra served asssets will be relative to your app's src/main/assets/ folder.
                        // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
                        // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
                        servedAssets =
                            listOf(
                                "flutter_assets/packages/flutter_readium/assets/.*",
                            ),
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
                    ),
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
            // This will automatically turn pages when tapping the screen edges or arrow keys.
            addInputListener(DirectionalNavigationAdapter(this))
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
     * re-add them manually — see CLAUDE.md "Prefer honest limitations over brittle workarounds".
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
         * background to transparent when a custom theme is active (see Gotcha in CLAUDE.md);
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
