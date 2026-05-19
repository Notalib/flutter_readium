import Flutter
import ReadiumNavigator
import ReadiumShared

/// Flutter platform-view identifier registered for the reader widget. Shared by
/// EPUB and PDF reader implementations — Dart never sees a different identifier
/// for different content types; dispatch happens inside `ReadiumReaderViewFactory`.
let readiumReaderViewType = "dk.nota.flutter_readium/ReadiumReaderWidget"

let ReadiumReaderStatusReady = "ready"
let ReadiumReaderStatusLoading = "loading"
let ReadiumReaderStatusClosed = "closed"
let ReadiumReaderStatusError = "error"

private let readerStatusJsonEncoder = JSONEncoder()

func emitReaderStatusChanged(status: String) {
  if let jsonData = try? readerStatusJsonEncoder.encode(status),
     let jsonString = String(data: jsonData, encoding: .utf8) {
    FlutterReadiumPlugin.instance?.readerStatusStreamHandler?.sendEvent(jsonString)
  }
}

final class ReadiumBugLogger: ReadiumShared.WarningLogger {
  func log(_ warning: Warning) {
    Log.reader.error("Error in Readium while deserializing: \(warning)")
  }
}

let readiumBugLogger = ReadiumBugLogger()

/// Common surface that both ``EPUBReaderView`` and ``PDFReaderView`` implement so
/// `FlutterReadiumPlugin` can hold a single `currentReaderView` reference and
/// dispatch the same handful of navigation / synchronisation calls regardless
/// of publication type.
///
/// EPUB-specific methods (`syncToLocator`, `applyDecorations`) are intentionally
/// part of the protocol. The PDF implementation accepts them and no-ops with a
/// warning — PDF has no media-overlay sync and no `DecorableNavigator`
/// conformance in swift-toolkit 3.7.0.
public protocol ReadiumReaderView: AnyObject {
  func getCurrentLocation() -> Locator?
  func getFirstVisibleLocator() async -> Locator?
  func goToLocator(_ locator: Locator, animated: Bool) async -> Bool
  func goToProgression(_ progression: Double, animated: Bool) async -> Bool
  func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval?) async -> Bool
  func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String)
  func onCustomEditingAction() -> Void
}
