package com.example.flutter_readium_example

import android.content.Context
import android.os.Bundle
import android.os.PersistableBundle
import android.util.AttributeSet
import android.util.Log
import android.view.View
// import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

private const val TAG = "MainActivity"

class MainActivity : FlutterFragmentActivity() {
    // override fun provideFlutterEngine(context: Context): FlutterEngine? =
    //   AudioServicePlugin.getFlutterEngine(context)
    override fun onCreate(savedInstanceState: Bundle?, persistentState: PersistableBundle?) {
        Log.d(TAG, "::onCreate")
        super.onCreate(savedInstanceState, persistentState)
    }

    override fun onStop() {
        Log.d(TAG, "::onStop")
        super.onStop()
    }

    override fun onResume() {
        Log.d(TAG, "::onResume")
        super.onResume()
    }

    override fun onPause() {
        Log.d(TAG, "::onPause")
        super.onPause()
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        Log.d(TAG, "::onRestoreInstanceState")
        super.onRestoreInstanceState(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.d(TAG, "::onSaveInstanceState")
        super.onSaveInstanceState(outState)

    }
}
