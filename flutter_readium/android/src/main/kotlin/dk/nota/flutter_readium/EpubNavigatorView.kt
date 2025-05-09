package dk.nota.flutter_readium

import android.annotation.SuppressLint
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.util.AttributeSet
import android.util.Log
import android.widget.LinearLayout
import io.flutter.FlutterInjector
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.epub.EpubPreferencesEditor
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.PreferencesEditor
import org.readium.r2.navigator.preferences.Theme
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
  context: Context, publication: Publication, initialLocator: Locator?,
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
    Log.d(TAG, "/********************************************\\")
    Log.d(
      TAG,
      "::setPublication (title=${publication.metadata.title}, baseUrl=${publication.baseUrl})"
    )

    // TODO: Remove this copy/paste from documentation
    // servedAssets:
    // Patterns for asset paths which will be available to EPUB resources under https://readium/assets/.
    // The patterns can use simple glob wildcards, see: https://developer.android.com/reference/android/os/PatternMatcher#PATTERN_SIMPLE_GLOB
    // Use .* to serve all app assets.

    // DFG: This will be relative to your app's src/main/assets/ folder
    // Underneath Readium is using https://developer.android.com/reference/androidx/webkit/WebViewAssetLoader.AssetsPathHandler
    val navigatorFactory = EpubNavigatorFactory(publication)
    val fragmentFactory = navigatorFactory.createFragmentFactory(
      configuration = EpubNavigatorFragment.Configuration(
        shouldApplyInsetsPadding = false,
        servedAssets = listOf(
          "comics.js",
          "comics.css",
          "epub.js",
          "epub.css",
        )
      ),
      initialLocator = initialLocator,
      listener = this,
      paginationListener = this,
      // initialPreferences = EpubPreferences(
      //   theme = Theme.SEPIA,
      //   scroll = false,
      //   backgroundColor = ReadiumColor(Color.CYAN)
      // )
    )

    editor = navigatorFactory.createPreferencesEditor(EpubPreferences(
      publisherStyles = false,
      theme = Theme.SEPIA,
      scroll = false,
      backgroundColor = ReadiumColor(Color.CYAN),
      textColor = ReadiumColor(Color.BLACK),
      fontFamily = FontFamily("sans-serif"),
      fontSize = 1.0,
      fontWeight = 1.0
    ))

    fragment = fragmentFactory.instantiate(
        activity.classLoader,
        EpubNavigatorFragment::class.java.name,
      ) as EpubNavigatorFragment
    if (isAttachedToWindow) {
      attachFragment()
    }
    Log.d(TAG, "\\********************************************/")
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
      // Readium bug, we never get here.
      Log.d(TAG, "GO returned.")
    } else {
      Log.d(TAG, "GO FAILED!")
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

  fun setPreferencesFromUserProperties(userProperties: Map<String, String>) {
    try {
      val newPreferences = EpubPreferences(
        fontFamily = userProperties["fontFamily"]?.let { FontFamily(it) } ?: editor.preferences.fontFamily,
        fontSize = userProperties["fontSize"]?.toDouble() ?: editor.preferences.fontSize,
        fontWeight = userProperties["fontWeight"]?.toDouble() ?: editor.preferences.fontWeight,
        scroll = userProperties["verticalScroll"]?.toBoolean() ?: editor.preferences.scroll,
        backgroundColor = userProperties["backgroundColor"]?.let { ReadiumColorFromCSS(it) } ?: editor.preferences.backgroundColor,
        textColor = userProperties["textColor"]?.let { ReadiumColorFromCSS(it) } ?: editor.preferences.textColor
      )
      this.editor.apply {
        fontFamily.set(newPreferences.fontFamily)
        fontSize.set(newPreferences.fontSize)
        fontWeight.set(newPreferences.fontWeight)
        scroll.set(newPreferences.scroll)
        backgroundColor.set(newPreferences.backgroundColor)
        textColor.set(newPreferences.textColor)
      }
      this.fragment.submitPreferences(editor.preferences)
    } catch (ex: Exception) {
      Log.e(TAG, "Error applying UserProperties as EpubPreferences: $ex")
    }
  }
}

private fun ReadiumColorFromCSS(cssColor: String): ReadiumColor {
  val color = Color.parseColor(cssColor)
  return ReadiumColor(color)
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
