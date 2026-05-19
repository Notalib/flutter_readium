package dk.nota.flutter_readium.navigators

import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commitNow
import dk.nota.flutter_readium.ReadiumReaderWidget.Companion.NAVIGATOR_FRAGMENT_TAG
import dk.nota.flutter_readium.fragments.PdfReaderFragment
import dk.nota.flutter_readium.models.PdfReaderViewModel
import dk.nota.flutter_readium.throttleLatest
import dk.nota.flutter_readium.withScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.adapter.pdfium.navigator.PdfiumEngineProvider
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.pdf.PdfNavigatorFactory
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "PdfNavigator"
private const val currentVisualLocatorKey = "currentVisualCurrentLocator"

/**
 * Wraps the Readium [PdfNavigatorFragment] (Pdfium-backed) inside the same
 * `BaseNavigator` shape that [EpubNavigator] uses, so the rest of the plugin
 * (ReadiumReader, ReadiumReaderWidget) can treat the two interchangeably.
 *
 * No preferences/decorations support yet — preferences land in Phase 5 of the
 * PDF support roadmap. Decorations are not exposed by the upstream PDF
 * navigator in kotlin-toolkit 3.1.2.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class PdfNavigator :
  BaseNavigator,
  PdfReaderFragment.Listener {
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

  private var pdfNavigator: PdfReaderFragment? = null

  val currentLocator
    get() = pdfNavigator?.currentLocator

  private val navigatorStarted
    get() = pdfNavigator!!.started

  override suspend fun initNavigator() {
    pdfNavigator =
      PdfReaderFragment().apply {
        vm =
          PdfReaderViewModel().apply {
            navigatorFactory =
              PdfNavigatorFactory(
                publication = publication,
                pdfEngineProvider = PdfiumEngineProvider(),
              )
            locator = this@PdfNavigator.initialLocator
            preferences = PdfiumPreferences()
          }
        listener = this@PdfNavigator
      }
  }

  fun attachNavigator(
    fragmentManager: FragmentManager,
    viewGroup: ViewGroup,
  ) {
    val navigator = pdfNavigator ?: return
    mainScope.launch {
      fragmentManager.commitNow {
        add(viewGroup, navigator, NAVIGATOR_FRAGMENT_TAG)
      }
    }
  }

  suspend fun go(
    locator: Locator,
    animated: Boolean,
  ): Boolean {
    val navigator = pdfNavigator
    if (navigator == null) {
      Log.d(TAG, "::go - pdfNavigator is null!")
      return false
    }
    Log.d(TAG, "::go $locator animated:$animated")
    return withScope(mainScope) {
      afterFragmentStarted()
      if (!navigator.go(locator, animated)) {
        Log.w(TAG, "::go - FAILED!")
        return@withScope false
      }
      return@withScope true
    }
  }

  suspend fun goBackward(animated: Boolean = true) {
    val navigator = pdfNavigator
    if (navigator == null) {
      Log.e(TAG, "::goBackward - pdfNavigator is null!")
      return
    }
    withScope(mainScope) {
      Log.d(TAG, "::goBackward")
      navigator.goBackward(animated)
    }
  }

  suspend fun goForward(animated: Boolean = true) {
    val navigator = pdfNavigator
    if (navigator == null) {
      Log.e(TAG, "::goForward - pdfNavigator is null!")
      return
    }
    withScope(mainScope) {
      Log.d(TAG, "::goForward")
      navigator.goForward(animated)
    }
  }

  override fun setupNavigatorListeners() {
    val navigator =
      pdfNavigator ?: run {
        Log.e(TAG, "::setupNavigatorListeners - pdfNavigator is null this should never happen")
        return
      }

    val currentLocator = navigator.currentLocator
    if (currentLocator != null) {
      currentLocator
        .throttleLatest(100.milliseconds)
        .distinctUntilChanged()
        .onEach { locator ->
          onCurrentLocatorChanges(locator)
          currentVisualLocator = locator
        }.launchIn(mainScope)
        .let { jobs.add(it) }
    } else {
      Log.d(TAG, "::setupNavigatorListeners - currentLocator is null - navigator not ready?")
    }
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
    setupNavigatorListeners()
  }

  override fun onPageChanged(
    pageIndex: Int,
    totalPages: Int,
    locator: Locator,
  ) {
    notifyIsReady()
    visualListener.onPageChanged(pageIndex, totalPages, locator)
    mainScope.launch {
      currentVisualLocator = locator
    }
  }

  override fun onExternalLinkActivated(url: AbsoluteUrl) {
    visualListener.onExternalLinkActivated(url)
  }

  override fun onCurrentLocatorChanges(locator: Locator) {
    visualListener.onVisualCurrentLocationChanged(locator)
  }

  override fun dispose() {
    super.dispose()
    mainScope.launch {
      pdfNavigator?.let { fragment ->
        fragment.parentFragmentManager.commitNow { remove(fragment) }
      }
      mainScope.coroutineContext.cancelChildren()
      pdfNavigator = null
    }
    state.clear()
  }

  private suspend fun afterFragmentStarted() {
    if (navigatorStarted.value) return
    navigatorStarted.first { it }
  }

  companion object {
    fun restoreState(
      publication: Publication,
      listener: EpubNavigator.VisualListener,
      state: Bundle,
    ): PdfNavigator {
      val locator =
        state
          .getString(currentVisualLocatorKey)
          ?.let { json -> Locator.fromJSON(JSONObject(json)) }
      Log.d(TAG, "::restoreState - locator: $locator")
      return PdfNavigator(publication, locator, listener)
    }
  }
}
