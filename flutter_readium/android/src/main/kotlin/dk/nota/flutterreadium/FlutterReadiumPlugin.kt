package dk.nota.flutterreadium

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.ExperimentalCoroutinesApi

private const val TAG = "FlutterReadiumPlugin"

@ExperimentalCoroutinesApi
class FlutterReadiumPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    /**
     * The MethodChannel that will the communication between Flutter and native Android
     *
     * This local reference serves to register the plugin with the Flutter Engine and unregister it
     * when the Flutter Engine is detached from the Activity
     */
    private lateinit var publicationChannel: MethodChannel

    private lateinit var publicationMethodCallHandler: PublicationMethodCallHandler

    private lateinit var binaryMessenger: BinaryMessenger

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPluginBinding) {
        PluginLog.i(TAG, "onAttachedToEngine")
        binaryMessenger = flutterPluginBinding.binaryMessenger

        // Register reader view factory
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE_CHANNEL_NAME,
            ReadiumReaderViewFactory(binaryMessenger),
        )

        // Setup publication channel
        publicationMethodCallHandler = PublicationMethodCallHandler()
        publicationChannel = MethodChannel(binaryMessenger, publicationChannelName)
        publicationChannel.setMethodCallHandler(publicationMethodCallHandler)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        PluginLog.d(TAG, "onMethodCall")
        result.notImplemented()
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        PluginLog.i(TAG, "onDetachedFromEngine")
        ReadiumReader.detach()
        publicationChannel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        PluginLog.i(TAG, "onAttachedToActivity")

        ReadiumReader.attach(binding.activity, binaryMessenger)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        PluginLog.d(TAG, "onDetachedFromActivityForConfigChanges")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        PluginLog.d(TAG, "onReattachedToActivityForConfigChanges")
    }

    override fun onDetachedFromActivity() {
        PluginLog.i(TAG, "onDetachedFromActivity")
        ReadiumReader.detach()
    }
}
