package dk.nota.flutter_readium

import android.content.Context
import android.util.Log
import androidx.core.net.toUri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.IOException


//internal const val publicationChannelName = "dk.nota.flutter_readium/main"

internal var pluginAppContext: Context? = null

class FlutterReadiumPlugin : FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var publicationChannel: MethodChannel

  private lateinit var publicationMethodCallHandler: PublicationMethodCallHandler

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPluginBinding) {
    val messenger = flutterPluginBinding.binaryMessenger

    pluginAppContext = flutterPluginBinding.applicationContext

    // Register reader view factory
    flutterPluginBinding.platformViewRegistry.registerViewFactory(
      viewTypeChannelName,
      ReadiumReaderViewFactory(messenger)
    )

    // TODO: Remove this, just for debugging.
    val files = listAssetFiles(flutterPluginBinding.applicationContext, "flutter_assets/packages/flutter_readium/assets/helpers")
    for (file in files) {
      Log.i("ListAssetFiles", "Asset: ${file.toUri()}")
    }

    // Setup publication channel
    publicationMethodCallHandler =
      PublicationMethodCallHandler(flutterPluginBinding.applicationContext)
    publicationChannel = MethodChannel(messenger, publicationChannelName)
    publicationChannel.setMethodCallHandler(publicationMethodCallHandler)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    result.notImplemented()
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    publicationChannel.setMethodCallHandler(null)
  }

  fun listAssetFiles(c: Context, rootPath: String): List<String> {
    Log.i("ListAssetFiles", "Listing assets in $rootPath")
    val files: MutableList<String> = ArrayList()
    try {
      val Paths = c.assets.list(rootPath)
      if (Paths!!.isNotEmpty()) {
        // This is a folder
        for (file in Paths) {
          val path = "$rootPath/$file"
          if (File(path).isDirectory()) files.addAll(listAssetFiles(c, path))
          else files.add(path)
        }
      }
    } catch (e: IOException) {
      e.printStackTrace()
    }
    return files
  }

}
