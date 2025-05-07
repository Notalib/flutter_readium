import Flutter
import UIKit

public class FlutterReadiumPlugin: NSObject, FlutterPlugin {
  static var registrar: FlutterPluginRegistrar? = nil

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dk.nota.flutter_readium/main", binaryMessenger: registrar.messenger())
    let instance = FlutterReadiumPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Register reader view factory
    let factory = ReadiumReaderViewFactory(registrar: registrar)
    registrar.register(factory, withId: readiumReaderViewType)

    self.registrar = registrar
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCustomHeaders":
      // TODO: Implement like this or make an init?
      break
    case "openPublication":
      publicationMethodCallHandler(call: call, result: result)
      break
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
