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
    invokeMethod("onPageChanged", arguments: try? locator.jsonString())
  }

  func onExternalLinkActivated(url: URL) {
    invokeMethod("onExternalLinkActivated", arguments: url.absoluteString as String?)
  }

  func onTextSelected(locator: Locator, selectedText: String?) {
    var json: [String: Any] = [:]
    if let locatorString = try? locator.jsonString(),
       let locatorData = locatorString.data(using: .utf8),
       let locatorJson = try? JSONSerialization.jsonObject(with: locatorData) {
      json["locator"] = locatorJson
    }
    if let selectedText = selectedText {
      json["selectedText"] = selectedText
    }
    if let data = try? JSONSerialization.data(withJSONObject: json),
       let jsonString = String(data: data, encoding: .utf8) {
      invokeMethod("onTextSelected", arguments: jsonString)
    }
  }

  func onSelectionAction(actionId: String, locator: Locator, selectedText: String?) {
    var json: [String: Any] = ["actionId": actionId]
    if let locatorString = try? locator.jsonString(),
       let locatorData = locatorString.data(using: .utf8),
       let locatorJson = try? JSONSerialization.jsonObject(with: locatorData) {
      json["locator"] = locatorJson
    }
    if let selectedText = selectedText {
      json["selectedText"] = selectedText
    }
    if let data = try? JSONSerialization.data(withJSONObject: json),
       let jsonString = String(data: data, encoding: .utf8) {
      invokeMethod("onSelectionAction", arguments: jsonString)
    }
  }

  func onDecorationInteraction(decorationId: String, group: String, type: String, locator: Locator?) {
    var json: [String: Any] = [
      "decorationId": decorationId,
      "group": group,
      "type": type,
    ]
    if let locator = locator,
       let locatorString = try? locator.jsonString(),
       let locatorData = locatorString.data(using: .utf8),
       let locatorJson = try? JSONSerialization.jsonObject(with: locatorData) {
      json["locator"] = locatorJson
    }
    if let data = try? JSONSerialization.data(withJSONObject: json),
       let jsonString = String(data: data, encoding: .utf8) {
      invokeMethod("onDecorationInteraction", arguments: jsonString)
    }
  }
}
