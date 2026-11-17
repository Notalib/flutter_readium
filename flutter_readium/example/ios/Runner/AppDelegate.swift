import Flutter
import UIKit
import flutter_readium
import flutter_readium_lcp

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Test-only basic-profile client. A real app hands over its licensed EDRLab client here.
    FlutterReadiumLcpPlugin.lcpClient = BasicProfileLCPClient()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc func onCustomEditingAction() {
    debugPrint("AppDelegate.onCustomEditingAction")
    // TODO: Test if this works, it should trigger a custom action response.
    flutter_readium.FlutterReadiumPlugin.instance?.currentReaderView?.onCustomEditingAction()
  }
}