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
    override fun onCreate(savedInstanceState: Bundle?, persistentState: PersistableBundle?) {
        Log.d(TAG, "::onCreate($savedInstanceState, $persistentState)")
        super.onCreate(savedInstanceState, persistentState)
    }

    override fun onStop() {
        try {
            Log.d(TAG, "::onStop")
            super.onStop()
        } finally {
            Log.d(TAG, "::onStop - ended")
        }
    }

    override fun onResume() {
        try {
            Log.d(TAG, "::onResume")
            super.onResume()
        } finally {
            Log.d(TAG, "::onResume - ended")
        }
    }

    override fun onPause() {
        try {
            Log.d(TAG, "::onPause")
            super.onPause()
        } finally {
            Log.d(TAG, "::onPause - ended")
        }
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        Log.d(TAG, "::onRestoreInstanceState")
        super.onRestoreInstanceState(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.d(TAG, "::onSaveInstanceState")
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        try {
            Log.d(TAG, "::onDestroy")
            super.onDestroy()
        } finally {
            Log.d(TAG, "::onDestroy - ended")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            Log.d(TAG, "::onCreate($savedInstanceState)")
            super.onCreate(savedInstanceState)
        } finally {
            Log.d(TAG, "::onCreate($savedInstanceState) - ended")
        }
    }

    override fun onStart() {
        Log.d(TAG, "::onStart")
        super.onStart()
    }

    override fun onAttachedToWindow() {
        Log.d(TAG, "::onAttachedToWindow")
        super.onAttachedToWindow()
    }

    override fun onDetachedFromWindow() {
        Log.d(TAG, "::onAttachedToWindow")
        super.onDetachedFromWindow()
    }
}
