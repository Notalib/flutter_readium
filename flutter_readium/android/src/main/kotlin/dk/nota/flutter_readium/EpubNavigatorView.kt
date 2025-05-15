package dk.nota.flutter_readium

import android.annotation.SuppressLint
import android.content.Context
import android.content.ContextWrapper
import android.util.AttributeSet
import android.util.Log
import android.widget.LinearLayout
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private const val TAG = "EpubNavigatorView"

@SuppressLint("ViewConstructor")
@OptIn(ExperimentalReadiumApi::class)
internal class EpubNavigatorView(
  context: Context,
  publication: Publication,
  initialLocator: Locator?,
  initialPreferences: EpubPreferences?,
  private val listener: Listener, attrs: AttributeSet? = null
) : LinearLayout(context, attrs), EpubNavigatorFragment.Listener,
  EpubNavigatorFragment.PaginationListener {
  interface Listener {
    fun onPageLoaded()
    fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator)
  }

  private var editor: EpubPreferencesEditor
  private val fragment: EpubNavigatorFragment

  private val activity
    get() = (context as ContextWrapper).baseContext as FragmentActivity
  private val fragmentManager
    get() = activity.supportFragmentManager

  /// Checks when the fragment starts and is safe to use.
  private val fragmentObserver = StartLifecycleObserver()

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

    // DFG: This will be relative to your app's src/main/assets/ folder.
    // To reference assets from other flutter packages use 'flutter_assets/packages/<package>/assets/.*'
    // Readium uses WebViewAssetLoader.AssetsPathHandler under the surface.
    val preferences = initialPreferences ?: EpubPreferences()
    val navigatorFactory = EpubNavigatorFactory(publication)
    val fragmentFactory = navigatorFactory.createFragmentFactory(
      configuration = EpubNavigatorFragment.Configuration(
        shouldApplyInsetsPadding = false,
        servedAssets = listOf(
          "flutter_assets/packages/flutter_readium/assets/.*",
        )
      ),
      initialLocator = initialLocator,
      listener = this,
      paginationListener = this,
      initialPreferences = preferences,
    )

    editor = navigatorFactory.createPreferencesEditor(preferences)

    fragment = fragmentFactory.instantiate(
        activity.classLoader,
        EpubNavigatorFragment::class.java.name,
      ) as EpubNavigatorFragment
    if (isAttachedToWindow) {
      attachFragment()
    }
  }

  private fun attachFragment() {
    fragment.lifecycle.addObserver(fragmentObserver)
    fragmentManager.beginTransaction().apply {
      add(id, fragment)
      commitNow()
    }
  }

  private fun detachFragment() {
    // Causes this error with some delay, unsure whether it matters:
    // E/chromium(13736): [ERROR:aw_browser_terminator.cc(125)] Renderer process (13879) crash detected (code -1).
    // Does a fragment actually need detaching when the view containing it is removed? Afraid of leaking fragments.
    fragmentManager.beginTransaction().apply {
      remove(fragment)
      try {
        commitNow()
      } catch (e: IllegalStateException) {
        Log.e(TAG, "::detachFragment $e")
      }
    }
    going?.resumeWith(unitResult)
    going = null
    fragment.lifecycle.removeObserver(fragmentObserver)
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

  internal val currentLocator get() = fragment.currentLocator.value
  suspend fun getFirstVisibleLocator() = fragment.firstVisibleElementLocator()

  override fun onPageLoaded() {
    Log.d(TAG, "::onPageLoaded")
    listener.onPageLoaded()

    going?.resumeWith(unitResult)
    going = null
  }

  internal suspend fun go(locator: Locator, animated: Boolean) {
    Log.d(TAG, "::go ${locator.href}")
    val fragment = this.fragment
    afterFragmentStarted()
    if (fragment.go(locator, animated)) {
      Log.d(TAG, "GO returned.")
    } else {
      Log.w(TAG, "GO FAILED!")
    }
  }

  internal suspend fun goLeft(animated: Boolean) {
    Log.d(TAG, "::goLeft")
    afterFragmentStarted()
    suspendCoroutine {
      if (fragment.goBackward(animated)) {
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
    afterFragmentStarted()
    suspendCoroutine {
      if (fragment.goForward(animated)) {
        Log.d(TAG, "::goRight: Went forward.")
        it.resume(Unit)
      } else {
        Log.d(TAG, "::goRight: Couldn't go forward.")
        it.resume(Unit)
      }
    }
  }

  internal suspend fun applyDecorations(
    decorations: List<Decoration>,
    group: String,
  ) {
    fragment.applyDecorations(decorations, group)
  }

  internal suspend fun evaluateJavascript(script: String): String? {
    // Make sure fragment has started, otherwise fragment.evaluateJavascript may fail early and
    // return null.
    afterFragmentStarted()

    val ret = fragment.evaluateJavascript(script)
    if (ret == null || ret == "null" || ret == "undefined") {
      // Hopefully can't happen.
      Log.e(TAG, "::evaluateJavascript($script) returned null")

      return null;
    }
    return ret
  }

  @ExperimentalReadiumApi
  override fun onExternalLinkActivated(url: AbsoluteUrl) {
    Log.w(TAG, "onExternalLinkActivated: $url -- BUT NOT IMPLEMENTED!")
  }

  internal suspend fun setPreferencesFromMap(userProperties: Map<String, String>) {
    try {
      val newPreferences = EpubPreferencesFromMap(userProperties, this.editor.preferences)
        ?: throw IllegalArgumentException("failed to deserialize map into EpubPreferences")

      this.editor.apply {
        fontFamily.set(newPreferences.fontFamily)
        fontSize.set(newPreferences.fontSize)
        fontWeight.set(newPreferences.fontWeight)
        scroll.set(newPreferences.scroll)
        backgroundColor.set(newPreferences.backgroundColor)
        textColor.set(newPreferences.textColor)
      }
      suspendCoroutine {
        fragment.submitPreferences(editor.preferences)
      }
    } catch (ex: Exception) {
      Log.e(TAG, "Error applying EpubPreferences: $ex")
    }
  }
}

private val unitResult = Result.success(Unit)

private class StartLifecycleObserver : DefaultLifecycleObserver {
  val started = MutableStateFlow(false)

  override fun onStart(owner: LifecycleOwner) {
    if (!started.value) {
      Log.d(TAG, "::onStart: First run")
      started.value = true
    }
  }
}
