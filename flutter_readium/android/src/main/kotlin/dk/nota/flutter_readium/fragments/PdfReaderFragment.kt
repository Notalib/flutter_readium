package dk.nota.flutter_readium.fragments

import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.fragment.app.commitNow
import androidx.lifecycle.lifecycleScope
import dk.nota.flutter_readium.R
import dk.nota.flutter_readium.ReadiumReader
import dk.nota.flutter_readium.models.PdfReaderViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import org.readium.adapter.pdfium.navigator.PdfiumNavigatorFragment
import org.readium.adapter.pdfium.navigator.PdfiumPreferences
import org.readium.r2.navigator.pdf.PdfNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.AbsoluteUrl

private const val TAG = "PdfReaderFragment"
private const val NAVIGATOR_FRAGMENT_TAG = "READIUM_PDF_READER_FRAGMENT"

private var instanceNo = 0

/**
 * Host fragment for the Readium PDF navigator. Mirrors [EpubReaderFragment] but
 * follows the upstream PDF test-app pattern: the navigator's
 * [androidx.fragment.app.FragmentFactory] must be installed on
 * `childFragmentManager` *before* `super.onCreate`, because
 * [PdfNavigatorFragment] has an `internal` constructor that only the
 * generated factory can invoke.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class PdfReaderFragment :
  VisualReaderFragment(),
  PdfNavigatorFragment.Listener,
  CoroutineScope by MainScope() {
  interface Listener {
    fun onPageChanged(
      pageIndex: Int,
      totalPages: Int,
      locator: Locator,
    )

    fun onExternalLinkActivated(url: AbsoluteUrl)
  }

  var listener: Listener? = null

  val started = MutableStateFlow(false)

  private val instance = ++instanceNo

  private var pdfNavigator
    get() = navigator as? PdfiumNavigatorFragment
    set(value) {
      navigator = value
    }

  private val pdfVm
    get() = vm as PdfReaderViewModel?

  /**
   * Synchronous wrappers around the navigator's `go*` methods so the
   * surrounding [dk.nota.flutter_readium.navigators.PdfNavigator] can await
   * fragment-startup before calling.
   */
  fun goBackward(animated: Boolean): Boolean {
    val nav = pdfNavigator
    if (nav == null) {
      Log.d(TAG, "::goBackward - $instance - navigator not ready")
      return false
    }
    return nav.goBackward(animated)
  }

  fun goForward(animated: Boolean): Boolean {
    val nav = pdfNavigator
    if (nav == null) {
      Log.d(TAG, "::goForward - $instance - navigator not ready")
      return false
    }
    return nav.goForward(animated)
  }

  @OptIn(org.readium.r2.shared.ExperimentalReadiumApi::class)
  fun updatePreferences(preferences: PdfiumPreferences) {
    val nav = pdfNavigator
    if (nav == null) {
      Log.d(TAG, "::updatePreferences - $instance - navigator not ready")
      return
    }
    nav.submitPreferences(preferences)
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    Log.d(TAG, "::onCreate - $instance")
    val model = pdfVm
    val navigatorFactory = model?.navigatorFactory
    if (model == null || navigatorFactory == null) {
      Log.e(TAG, "::onCreate - $instance - missing view model or navigator factory")
      // Without a factory installed before super.onCreate, the FragmentManager
      // would crash when it tries to instantiate the (internal-ctor)
      // PdfNavigatorFragment. Install the dummy factory so the host can
      // gracefully fail rather than throw at restore time.
      childFragmentManager.fragmentFactory =
        PdfNavigatorFragment.createDummyFactory(
          pdfEngineProvider = org.readium.adapter.pdfium.navigator.PdfiumEngineProvider(),
        )
      super.onCreate(savedInstanceState)
      return
    }

    childFragmentManager.fragmentFactory =
      navigatorFactory.createFragmentFactory(
        initialLocator = model.locator,
        initialPreferences = model.preferences,
        listener = this,
      )
    super.onCreate(savedInstanceState)
  }

  override fun onViewCreated(
    view: View,
    savedInstanceState: Bundle?,
  ) {
    try {
      super.onViewCreated(view, savedInstanceState)
      Log.d(TAG, "::onViewCreated - $instance")

      val model = pdfVm
      if (model == null || model.navigatorFactory == null) {
        Log.e(TAG, "::onViewCreated - $instance - missing model / factory")
        return
      }

      attachingNavigatorFragment = true

      lifecycleScope.launch {
        if (ReadiumReader.currentPublication != null) {
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

  override fun onResume() {
    try {
      Log.d(TAG, "::onResume - $instance - attaching=$attachingNavigatorFragment")
      if (pdfVm == null) {
        Log.d(TAG, "::onResume - $instance - missing view model")
        return
      }
      if (attachingNavigatorFragment) {
        Log.d(TAG, "::onResume - $instance - don't attach navigator")
        return
      }
      attachNavigator()
    } finally {
      super.onResume()
    }
  }

  override fun onPause() {
    try {
      Log.d(TAG, "::onPause - $instance")
      pdfVm?.locator = currentLocator?.value
      pdfNavigator?.let { fragment ->
        childFragmentManager.commitNow { remove(fragment) }
      }
      pdfNavigator = null
      started.value = false
      attachingNavigatorFragment = false
    } finally {
      super.onPause()
    }
  }

  private var attachingNavigatorFragment = false

  private fun attachNavigator() {
    Log.d(TAG, "::attachNavigator() - $instance")
    if (navigator != null) {
      Log.d(TAG, "::attachNavigator() - $instance - already attached")
      return
    }

    if (ReadiumReader.currentPublication == null) {
      Log.e(TAG, "::attachNavigator() - $instance - missing publication")
      return
    }

    // The FragmentFactory was already installed in onCreate. We instantiate by
    // class name via `replace`, and the FragmentManager calls the factory.
    childFragmentManager.commitNow {
      replace(
        R.id.fragment_reader_container,
        PdfNavigatorFragment::class.java,
        Bundle(),
        NAVIGATOR_FRAGMENT_TAG,
      )
    }

    val pdfNav =
      childFragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG) as? PdfiumNavigatorFragment
    if (pdfNav == null) {
      Log.e(TAG, "::attachNavigator() - $instance - failed to retrieve PdfNavigatorFragment")
      return
    }
    pdfNavigator = pdfNav
    Log.d(TAG, "::attachNavigator() - $instance - got navigator = $pdfNav")

    // PDF has no PaginationListener equivalent — emit page-changed events by
    // observing the navigator's currentLocator. Locator.locations.position is
    // 1-based across both swift and kotlin Readium toolkits (kotlin-toolkit
    // 3.1.2 confirmed), so it maps 1:1 to a page number.
    lifecycleScope.launch {
      // PdfiumNavigatorFragment emits an initial locator with `position == null`
      // before layout settles. Skip those rather than fabricate a page number;
      // the next emission carries the real 1-based page position.
      pdfNav.currentLocator.collect { locator ->
        val pageIndex = locator.locations.position ?: return@collect
        val totalPages =
          ReadiumReader.currentPublication?.metadata?.numberOfPages ?: 1
        listener?.onPageChanged(pageIndex, totalPages, locator)
      }
    }

    started.value = true
  }
}
