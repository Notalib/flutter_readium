import Cocoa
import FlutterMacOS

/// No-op stub for the Flutter macOS desktop target (`flutter run -d macos`).
///
/// Native macOS desktop is not supported — the upstream Readium swift-toolkit is
/// iOS-only (links UIKit; see readium/swift-toolkit#783). This stub exists so
/// host apps that include `flutter_readium` can still compile and launch with the
/// macOS desktop target. All reader calls return `FlutterMethodNotImplemented`.
///
/// To read publications on a Mac, ship the iOS build and run it on an Apple
/// Silicon Mac via "Designed for iPad" — the iOS plugin works unmodified there.
public class FlutterReadiumPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_readium", binaryMessenger: registrar.messenger)
    let instance = FlutterReadiumPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
