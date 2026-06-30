import ReadiumNavigator
import ReadiumShared
import Flutter
import UIKit

public class PDFReaderView: NSObject, FlutterPlatformView, ReadiumReaderView, PDFNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private let _view: UIView
  private let pdfViewController: PDFNavigatorViewController
  private var hasSentReady = false
  private var isJumpingToLocator = false
  private let publication: Publication
  private var lastViewport: NavigatorViewport?

  var publicationIdentifier: String?

  public func view() -> UIView {
    Log.reader.debug("getView")
    return _view
  }

  deinit {
    Log.reader.info("deinit PDFReaderView")
    pdfViewController.view.removeFromSuperview()
    pdfViewController.delegate = nil
    channel.setMethodCallHandler(nil)
    FlutterReadiumPlugin.instance?.clearCurrentReaderView(ifIs: self)
  }

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    registrar: FlutterPluginRegistrar
  ) {
    Log.reader.info("init")
    let creationParams = args as! Dictionary<String, Any?>

    let publication = FlutterReadiumPlugin.instance!.getCurrentPublication()!
    self.publication = publication
    self.publicationIdentifier = publication.metadata.identifier

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator(legacyJSONString: locatorStr!)
    Log.reader.debug("publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())

    emitReaderStatusChanged(status: ReadiumReaderStatusLoading)

    Log.reader.info("Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")
    Log.reader.info("Added PDF publication at \(String(describing: publication.baseURL))")

    let config = PDFNavigatorViewController.Configuration()

    pdfViewController = try! PDFNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config
    )

    _view = UIView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    pdfViewController.delegate = self

    let child: UIView = pdfViewController.view
    let view = _view
    view.addSubview(pdfViewController.view)

    child.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate(
      [
        child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        child.topAnchor.constraint(equalTo: view.topAnchor),
        child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
      ]
    )

    FlutterReadiumPlugin.instance?.registerAsCurrentReaderView(self)

    /// This adapter will automatically turn pages when the user taps the
    /// screen edges or presses arrow keys.
    DirectionalNavigationAdapter(
      pointerPolicy: .init(types: [.mouse, .touch])
    ).bind(to: pdfViewController)

    Log.reader.debug("init success")
  }

  // MARK: - PDFNavigatorDelegate / NavigatorDelegate

  public func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    // All margin & safe-area is handled on the Flutter side.
    return .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    Log.reader.error("Should present error: \(error)")
  }

  public func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    Log.reader.warn("didFailToLoadResourceAt: \(href). err: \(error)")
    emitReaderStatusChanged(status: ReadiumReaderStatusError)

    let payload = FlutterReadiumError(message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(payload.toJsonString())
  }

  public func navigator(_ navigator: any Navigator, didJumpTo locator: Locator) {
    Log.reader.debug("didJumpTo: \(locator)")
    isJumpingToLocator = false
  }

  public func navigator(_ navigator: any ViewportObservingNavigator, viewportDidChange viewport: NavigatorViewport?) {
    lastViewport = viewport
  }

  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    Log.reader.debug("locationDidChange: \(locator)")
    if (!hasSentReady) {
      emitReaderStatusChanged(status: ReadiumReaderStatusReady)
      hasSentReady = true
    }
    emitOnPageChanged(locator: locator)
  }

  public func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      Log.reader.warn("skipped non-http external URL: \(url)")
      return
    }
    emitOnExternalLinkActivated(url: url)
  }

  // MARK: - ReadiumReaderView protocol

  public func getCurrentLocation() -> Locator? {
    return self.pdfViewController.currentLocation
  }

  public func getFirstVisibleLocator() async -> Locator? {
    // PDF shows a single page at a time — the current location is the first
    // (and only) visible locator.
    return self.pdfViewController.currentLocation
  }

  public func goToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    Log.reader.debug("goToLocator: \(locator)")
    isJumpingToLocator = true
    return await pdfViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  public func goToProgression(_ progression: Double, animated: Bool) async -> Bool {
    Log.reader.debug("goToProgression: \(progression)")
    guard let totalPages = publication.metadata.numberOfPages, totalPages > 0 else {
      Log.reader.warn("goToProgression: numberOfPages unknown, cannot navigate.")
      return false
    }
    let coerced = min(max(progression, 0.0), 1.0)
    let targetPage = Int((coerced * Double(totalPages - 1)).rounded()) + 1
    let clampedPage = min(max(targetPage, 1), totalPages)
    Log.reader.debug("goToProgression: progression=\(coerced) -> page \(clampedPage)/\(totalPages)")

    guard let currentLocator = getCurrentLocation() else {
      return false
    }
    let newLocator = currentLocator.copy(locations: { locs in
      locs.fragments = []
      locs.otherLocations = [:]
      locs.progression = coerced
      locs.position = clampedPage
    })
    return await pdfViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }

  public func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval?, isWordRange: Bool) async -> Bool {
    // PDF has no media-overlay or pre-recorded-audio sync to honour.
    Log.reader.debug("syncToLocator: ignored for PDF")
    return false
  }

  public func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    // PDFNavigatorViewController does not conform to DecorableNavigator in
    // swift-toolkit 3.9.0. Surface the call but no-op.
    Log.reader.debug("applyDecorations: not supported for PDF (group=\(groupIdentifier), count=\(decorations.count))")
  }

  public func onCustomEditingAction() -> Void {
    Log.reader.debug("onCustomEditingAction: not supported for PDF")
  }

  public func setMOActive(_ active: Bool) {
    // PDF has no CSS column layout — no-op.
  }

  // MARK: - Locator emission

  private func emitOnPageChanged(locator: Locator) -> Void {
    Log.reader.debug("emitOnPageChanged, locator: \(locator)")

    Task.detached(priority: .high) { [locator] in
      var resultLocator = locator

      // PDF TOC enrichment: find the last TOC entry whose "#page=N" fragment
      // is ≤ the current position, then attach its href and title to the locator.
      if let position = locator.locations.position {
        let tocEntry = await self.publication.getFlattenedToC()
          .compactMap { link -> (Int, Link)? in
            let parts = link.href.components(separatedBy: "#")
            guard parts.count == 2,
                  let fragment = parts.last,
                  fragment.hasPrefix("page="),
                  let tocPage = Int(fragment.dropFirst(5)) else { return nil }
            return (tocPage, link)
          }
          .filter { $0.0 <= position }
          .max(by: { $0.0 < $1.0 })?.1
        if let entry = tocEntry {
          resultLocator.title = entry.title
          resultLocator.locations.otherLocations["tocHref"] = .string(entry.href)
        }
      }

      let finalLocator = resultLocator
      await MainActor.run() {
        self.channel.onPageChanged(locator: finalLocator)
        FlutterReadiumPlugin.instance?.textLocatorStreamHandler?.sendEvent(try? finalLocator.jsonString())
      }
    }
  }

  private func emitOnExternalLinkActivated(url: URL) {
    Log.reader.info("emitOnExternalLinkActivated: \(url)")
    Task.detached(priority: .high) {
      await MainActor.run() {
        self.channel.onExternalLinkActivated(url: url)
      }
    }
  }

  // MARK: - Flutter method-channel handler

  func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    Log.reader.debug("onMethodCall: \(call.method)")
    switch call.method {
    case "go":
      let args = call.arguments as! [Any?]
      let locator = try! Locator(legacyJSONString: args[0] as! String, warnings: readiumBugLogger)!
      let animated = args[1] as? Bool ?? false

      Task.detached(priority: .high) {
        let success = await self.goToLocator(locator, animated: animated)
        await MainActor.run() {
          result(success)
        }
      }
    case "goBackward":
      let animated = call.arguments as? Bool ?? false
      let navOptions = NavigatorGoOptions(animated: animated)
      let pdfViewController = self.pdfViewController

      Task.detached(priority: .high) {
        let success = await pdfViewController.goBackward(options: navOptions)
        await MainActor.run() {
          result(success)
        }
      }
    case "goForward":
      let animated = call.arguments as? Bool ?? false
      let navOptions = NavigatorGoOptions(animated: animated)
      let pdfViewController = self.pdfViewController

      Task.detached(priority: .high) {
        let success = await pdfViewController.goForward(options: navOptions)
        await MainActor.run() {
          result(success)
        }
      }
    case "setPreferences":
      let args = call.arguments as! [String: Any]
      let preferences = FlutterPDFPreferences(fromMap: args)
      pdfViewController.submitPreferences(preferences.readium)
      result(nil)
    case "applyDecorations":
      // PDF has no DecorableNavigator conformance — apply through the protocol
      // method, which logs and no-ops.
      let args = call.arguments as! [Any?]
      let identifier = args[0] as! String
      let decorationsStr = args[1] as! [String]
      guard let decorations = try? decorationsStr.map({ try Decoration(fromJson: $0) }) else {
        return result(FlutterError.init(
          code: "JSON mapping error",
          message: "Could not map decorations from JSON: \(decorationsStr)",
          details: nil))
      }
      applyDecorations(decorations, forGroup: identifier)
      result(nil)
    case "dispose":
      Log.reader.info("Disposing pdfViewController")
      pdfViewController.view.removeFromSuperview()
      pdfViewController.delegate = nil
      FlutterReadiumPlugin.instance?.clearCurrentReaderView(ifIs: self)
      emitReaderStatusChanged(status: ReadiumReaderStatusClosed)
      result(nil)
    default:
      Log.reader.warn("Unhandled call: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}
