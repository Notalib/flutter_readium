import Flutter
import UIKit
import flutter_readium

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @objc func onCustomEditingAction() {
    debugPrint("AppDelegate.onCustomEditingAction")
    // TODO: Test if this works, it should trigger a custom action response.
    flutter_readium.FlutterReadiumPlugin.instance?.currentReaderView?.onCustomEditingAction()
  }
}
