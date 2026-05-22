package com.example.flutter_readium_example

import android.content.Context
import android.os.Bundle
import android.os.PersistableBundle
import android.util.AttributeSet
import android.util.Log
import android.view.View
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

private const val TAG = "MainActivity"

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(
        savedInstanceState: Bundle?,
        persistentState: PersistableBundle?,
    ) {
        Log.i(TAG, "::onCreate($savedInstanceState, $persistentState)")
        super.onCreate(savedInstanceState, persistentState)
    }

    override fun onStop() {
        try {
            Log.i(TAG, "::onStop")
            super.onStop()
        } finally {
            Log.i(TAG, "::onStop - ended")
        }
    }

    override fun onResume() {
        try {
            Log.i(TAG, "::onResume")
            super.onResume()
        } finally {
            Log.i(TAG, "::onResume - ended")
        }
    }

    override fun onPause() {
        try {
            Log.i(TAG, "::onPause")
            super.onPause()
        } finally {
            Log.i(TAG, "::onPause - ended")
        }
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        Log.i(TAG, "::onRestoreInstanceState")
        super.onRestoreInstanceState(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        Log.i(TAG, "::onSaveInstanceState")
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        try {
            Log.i(TAG, "::onDestroy")
            super.onDestroy()
        } finally {
            Log.i(TAG, "::onDestroy - ended")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            Log.i(TAG, "::onCreate($savedInstanceState)")
            super.onCreate(savedInstanceState)
        } finally {
            Log.i(TAG, "::onCreate($savedInstanceState) - ended")
        }
    }

    override fun onStart() {
        Log.i(TAG, "::onStart")
        super.onStart()
    }

    override fun onAttachedToWindow() {
        Log.i(TAG, "::onAttachedToWindow")
        super.onAttachedToWindow()
    }

    override fun onDetachedFromWindow() {
        Log.i(TAG, "::onAttachedToWindow")
        super.onDetachedFromWindow()
    }
}
