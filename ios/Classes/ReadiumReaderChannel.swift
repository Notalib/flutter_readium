import ReadiumShared

class ReadiumReaderChannel: FlutterMethodChannel {
  // Compiles fine without this init, but then mysteriously crashes later with EXC_BAD_ACCESS when calling any member function later.
  init(name: String, binaryMessenger messenger: FlutterBinaryMessenger) {
    // after updating to version 3.22.1 of Flutter, this started crashing upon opening a pub. With an error about a call to unimplemented init(binaryMessenger:codec:taskQueue:)
    // using the init(binaryMessenger:codec:taskQueue:) instead of init(binaryMessenger:codec) seems to have fixex it.
    // no idea why this change was needed
    super.init(
      name: name, binaryMessenger: messenger, codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: nil)
  }
  
  func onPageChanged(locator: Locator) {
    invokeMethod("onPageChanged", arguments: locator.jsonString as String?)
  }
}
