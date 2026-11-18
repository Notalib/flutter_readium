import Flutter
import Foundation
import ReadiumShared
import UIKit

class ReadiumReaderViewFactory: NSObject, @preconcurrency FlutterPlatformViewFactory {
    private weak var registrar: FlutterPluginRegistrar?

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
    super.init()
  }

  @MainActor func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        // Dispatch on the current publication's format. The Dart side passes
        // identical creationParams regardless of content type; the native
        // factory picks the right reader.
        // The widget can be built when no publication is open natively, e.g. when the app restores
        // its own reader state after a cold start without reopening the publication. Report an
        // error and show an empty view instead of trapping.
        guard let publication = FlutterReadiumPlugin.instance?.getCurrentPublication(),
              let registrar else {
            Log.reader.error("Reader view created without an open publication")
            emitReaderStatusChanged(status: ReadiumReaderStatusError)
            return EmptyReaderView(frame: frame)
        }
        if Self.isPDFPublication(publication) {
            return PDFReaderView(
                frame: frame,
                viewIdentifier: viewId,
                arguments: args,
                registrar: registrar,
                publication: publication)
        }
        return EPUBReaderView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            registrar: registrar,
            publication: publication)
    }

  /// True if the publication should be rendered with the PDF navigator.
  /// Checks both the Readium PDF profile and the first reading-order entry's
  /// media type so we cover publications that don't declare the profile but
  /// have a single `application/pdf` resource.
  private static func isPDFPublication(_ publication: Publication) -> Bool {
    if publication.conforms(to: Publication.Profile.pdf) {
      return true
    }
    return publication.readingOrder.first?.mediaType == .pdf
  }

  // Undocumented, but boilerplate function required for creationParams to not silently become nil!
  // https://github.com/flutter/flutter/issues/28124
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Stand-in returned when no publication is open, so the platform view has something to host.
private final class EmptyReaderView: NSObject, FlutterPlatformView {
  private let emptyView: UIView

  init(frame: CGRect) {
    emptyView = UIView(frame: frame)
    super.init()
  }

  func view() -> UIView { emptyView }
}
