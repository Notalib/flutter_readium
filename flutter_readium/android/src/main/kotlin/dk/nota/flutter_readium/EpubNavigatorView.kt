package dk.nota.flutter_readium

import android.annotation.SuppressLint
import android.content.Context
import android.content.ContextWrapper
import android.os.Parcelable
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.widget.LinearLayout
import androidx.fragment.app.FragmentActivity
import dk.nota.flutter_readium.fragments.EpubReaderFragment
import dk.nota.flutter_readium.models.EpubReaderViewModel
import kotlinx.coroutines.flow.first
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.coroutines.Continuation

private const val TAG = "EpubNavigatorView"

@SuppressLint("ViewConstructor")
internal class EpubNavigatorView(
  context: Context,
  pubIdentifier: String,
  pubUrl: String,
  publication: Publication,
  initialLocator: Locator?,
  initialPreferences: EpubPreferences?,
  private val listener: Listener, attrs: AttributeSet? = null
) : LinearLayout(context, attrs), EpubReaderFragment.Listener {
  interface Listener {
    fun onPageLoaded()
    fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
    fun onExternalLinkActivated(url: AbsoluteUrl)
  }

  private val navigator: EpubReaderFragment

  private val activity
    get() = (context as ContextWrapper).baseContext as FragmentActivity
  private val fragmentManager
    get() = activity.supportFragmentManager

  /// Checks when the fragment starts and is safe to use.
  private val fragmentObserver get() = navigator.fragmentObserver

  private var going = null as Continuation<Unit>?

  init {
    id = generateViewId()

    // By default, Readium applies some extra padding internally.
    // It was from r2-navigator-kotlin/r2-navigator/src/main/res/values/dimens.xml, and used by
    // r2-navigator-kotlin/r2-navigator/src/main/java/org/readium/r2/navigator/pager/R2EpubPageFragment.kt.
    // Overriding with <dimen name="r2.navigator.epub.vertical_padding">0dp</dimen> seems to work.
    Log.d(
      TAG,
      "setPublication (title=${publication.metadata.title}, baseUrl=${publication.baseUrl})"
    )

    navigator = EpubReaderFragment()
    navigator.vm = EpubReaderViewModel().let()
    {
      it.identifier = pubIdentifier
      it.pubUrl = pubUrl
      it.publication = publication
      it.locator = initialLocator
      it.preferences = initialPreferences

      it
    }
    navigator.listener = this
    if (isAttachedToWindow) {
      attachFragment()
    }
  }

  private fun attachFragment() {
    Log.d(TAG, "::attachFragment")

    fragmentManager.beginTransaction().apply {
      add(id, navigator)
      commitNow()
    }
  }

  private fun detachFragment() {
    Log.d(TAG, "::detachFragment")
  
    // Causes this error with some delay, unsure whether it matters:
    // E/chromium(13736): [ERROR:aw_browser_terminator.cc(125)] Renderer process (13879) crash detected (code -1).
    // Does a fragment actually need detaching when the view containing it is removed? Afraid of leaking fragments.
    fragmentManager.beginTransaction().apply {
      remove(navigator)
      try {
        commitNow()
      } catch (e: IllegalStateException) {
        Log.e(TAG, "::detachFragment $e")
      }
    }
    
    going?.resumeWith(unitResult)
    going = null
  }

  override fun onAttachedToWindow() {
    Log.d(TAG, "::onAttachedToWindow")
    super.onAttachedToWindow()
    attachFragment()
  }

  override fun onDetachedFromWindow() {
    Log.d(TAG, "::onDetachedFromWindow")
    detachFragment()
    super.onDetachedFromWindow()
  }

  override fun onSaveInstanceState(): Parcelable? {
    Log.d(TAG, "::onSaveInstanceState")
    return super.onSaveInstanceState()
  }

  override fun onRestoreInstanceState(state: Parcelable?) {
    Log.d(TAG, "::onRestoreInstanceState")
    super.onRestoreInstanceState(state)
  }

  override fun onViewAdded(child: View?) {
    super.onViewAdded(child)
    Log.d(TAG, "::onViedAdded $child")
  }

  override fun onViewRemoved(child: View?) {
    super.onViewRemoved(child)
    Log.d(TAG, "::onViewRemoved $child")
  }

  override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
    Log.d(
      TAG,
      "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression}"
    )
    listener.onPageChanged(pageIndex, totalPages, locator)
    going?.resumeWith(unitResult)
    going = null
  }

  private suspend fun afterFragmentStarted() {
    if (!fragmentObserver.started.value) {
      fragmentObserver.started.first { it }
      Log.d(TAG, "::afterFragmentStarted: Resuming call")
    }
  }

  internal val currentLocator get() = navigator.currentLocator?.value
  suspend fun firstVisibleElementLocator() = navigator.firstVisibleElementLocator()

  override fun onPageLoaded() {
    Log.d(TAG, "::onPageLoaded")
    listener.onPageLoaded()

    going?.resumeWith(unitResult)
    going = null
  }

  override fun onExternalLinkActivated(url: AbsoluteUrl) {
    listener.onExternalLinkActivated(url)
  }

  internal suspend fun go(locator: Locator, animated: Boolean) {
    Log.d(TAG, "::go ${locator.href}")
    navigator.apply {
      afterFragmentStarted()
      if (go(locator, animated)) {
        Log.d(TAG, "GO returned.")
      } else {
        Log.w(TAG, "GO FAILED!")
      }
    }
  }

  internal suspend fun goLeft(animated: Boolean) {
    Log.d(TAG, "::goLeft")
    afterFragmentStarted()
    navigator.goLeft(animated)
  }

  internal suspend fun goRight(animated: Boolean) {
    Log.d(TAG, "::goRight")
    afterFragmentStarted()
    navigator.goRight(animated)
  }

  internal suspend fun applyDecorations(
    decorations: List<Decoration>,
    group: String,
  ) {
    navigator.applyDecorations(decorations, group)
  }

  internal suspend fun evaluateJavascript(script: String): String? {
    // Make sure fragment has started, otherwise fragment.evaluateJavascript may fail early and
    // return null.
    afterFragmentStarted()

    val ret = navigator.evaluateJavascript(script)
    if (ret == null || ret == "null" || ret == "undefined") {
      // Hopefully can't happen.
      Log.e(TAG, "::evaluateJavascript($script) returned null $ret")

      return null
    }
    return ret
  }

  internal suspend fun setPreferences(preferences: EpubPreferences) {
    navigator.setPreferences(preferences)
  }
}

private val unitResult = Result.success(Unit)

