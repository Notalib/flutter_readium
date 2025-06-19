import Flutter
import ReadiumShared

class ReadiumReaderChannel: FlutterMethodChannel {
  // Compiles fine without this init, but then mysteriously crashes later with EXC_BAD_ACCESS when calling any member function later.
  init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {
    super.init(
      name: name, binaryMessenger: messenger, codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: nil)
  }

  func onPageChanged(locator: Locator) {
    invokeMethod("onPageChanged", arguments: locator.jsonString as String?)
  }

  func onExternalLinkActivated(url: URL) {
    invokeMethod("onExternalLinkActivated", arguments: url.absoluteString as String?)
  }
}
