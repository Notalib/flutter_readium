import Flutter
import UIKit
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

let utilsChannelName = "dk.nota.flutter_readium/Utils"

public class SwiftR2NavigatorFlutterPlugin: NSObject, FlutterPlugin {
  static var registrar: FlutterPluginRegistrar? = nil

  private var pubChannel: FlutterMethodChannel?
  private var utilsChannel: FlutterMethodChannel?
  private let pubChannelHandler = SwiftR2PublicationChannel()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftR2NavigatorFlutterPlugin()

    // Register reader view factory
    let factory = ReadiumReaderViewFactory(registrar: registrar)
    registrar.register(factory, withId: readiumReaderViewType)

    // Setup publication channel
    instance.pubChannel = FlutterMethodChannel(
      name: publicationChannelName, binaryMessenger: registrar.messenger())
    instance.pubChannel?.setMethodCallHandler(instance.pubChannelHandler.handleMethodCall)

    // Setup utils channel
    instance.utilsChannel = FlutterMethodChannel(
      name: utilsChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.utilsChannel!)

    // Set it to .debug only while debugging the readium
    ReadiumEnableLog(withMinimumSeverityLevel: .debug)

    self.registrar = registrar
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getFreeDiskSpaceInMB" {
      result(UIDevice.current.freeDiskSpaceInMB)
      return
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}
