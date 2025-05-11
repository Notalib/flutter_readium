package dk.nota.flutter_readium

import android.content.Context
import android.os.Environment
import android.os.StatFs
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

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
      viewType,
      ReadiumReaderViewFactory(messenger)
    )

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

}
