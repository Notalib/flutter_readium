package dk.nota.flutter_readium

import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow

class StartLifecycleObserver(private val tag: String): DefaultLifecycleObserver {
  val started = MutableStateFlow(false)

  override fun onStart(owner: LifecycleOwner) {
    val firstRun = !started.value
      Log.d(tag, "Fragment: onStart: First run? $firstRun")
    if (firstRun) {
      started.value = true
    }
  }

  override fun onPause(owner: LifecycleOwner) {
      Log.d(tag, "Fragment: onPause")
    super.onPause(owner)
  }

  override fun onDestroy(owner: LifecycleOwner) {
      Log.d(tag, "Fragment: onDestroy")
    super.onDestroy(owner)
  }

  override fun onCreate(owner: LifecycleOwner) {
      Log.d(tag, "Fragment: onCreate")
    super.onCreate(owner)
  }

  override fun onResume(owner: LifecycleOwner) {
      Log.d(tag, "Fragment: onResume")
    super.onResume(owner)
  }

  override fun onStop(owner: LifecycleOwner) {
      Log.d(tag, "Fragment: onStop")
    super.onStop(owner)
  }
}