import ReadiumNavigator
import ReadiumAdapterGCDWebServer
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

  var publicationIdentifier: String?

  public func view() -> UIView {
    Log.reader.debug("getView")
    return _view
  }

  deinit {
    Log.reader.info("dispose")
    pdfViewController.view.removeFromSuperview()
    pdfViewController.delegate = nil
    channel.setMethodCallHandler(nil)
    FlutterReadiumPlugin.instance?.setCurrentReadiumReaderView(nil)
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
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
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
      config: config,
      httpServer: sharedReadium.httpServer!
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

    FlutterReadiumPlugin.instance?.setCurrentReadiumReaderView(self)

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

  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    Log.reader.debug("onPageChanged: \(locator)")
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
    guard let locator = getCurrentLocation() else {
      return false
    }
    let newLocator = locator.copyWithProgressionLocations(progression: progression)
    return await pdfViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }

  public func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval?) async -> Bool {
    // PDF has no media-overlay or pre-recorded-audio sync to honour.
    Log.reader.debug("syncToLocator: ignored for PDF")
    return false
  }

  public func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    // PDFNavigatorViewController does not conform to DecorableNavigator in
    // swift-toolkit 3.7.0. Surface the call but no-op.
    Log.reader.debug("applyDecorations: not supported for PDF (group=\(groupIdentifier), count=\(decorations.count))")
  }
  
  public func onCustomEditingAction() -> Void {
    Log.reader.debug("onCustomEditingAction: not supported for PDF")
  }

  // MARK: - Locator emission

  private func emitOnPageChanged(locator: Locator) -> Void {
    Log.reader.debug("emitOnPageChanged, locator: \(locator)")

    // PDF locators carry `locations.position` (1-based page number) and
    // `fragments: ["page=N"]` from the upstream `PDFPositionsService` — forward
    // them as-is. TOC-link enrichment is EPUB-specific (cssSelector based) and
    // is reintroduced for PDFs in a later phase.
    Task.detached(priority: .high) { [locator] in
      await MainActor.run() {
        self.channel.onPageChanged(locator: locator)
        FlutterReadiumPlugin.instance?.textLocatorStreamHandler?.sendEvent(locator.jsonString)
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
      let locator = try! Locator(jsonString: args[0] as! String, warnings: readiumBugLogger)!
      let animated = args[1] as! Bool

      Task.detached(priority: .high) {
        let success = await self.goToLocator(locator, animated: animated)
        await MainActor.run() {
          result(success)
        }
      }
    case "goBackward":
      let animated = call.arguments as! Bool
      let navOptions = NavigatorGoOptions(animated: animated)
      let pdfViewController = self.pdfViewController

      Task.detached(priority: .high) {
        let success = await pdfViewController.goBackward(options: navOptions)
        await MainActor.run() {
          result(success)
        }
      }
    case "goForward":
      let animated = call.arguments as! Bool
      let navOptions = NavigatorGoOptions(animated: animated)
      let pdfViewController = self.pdfViewController

      Task.detached(priority: .high) {
        let success = await pdfViewController.goForward(options: navOptions)
        await MainActor.run() {
          result(success)
        }
      }
    case "setPreferences":
      // PDF preferences are deferred to a later phase. Acknowledge the call so
      // the Dart side doesn't see a `MethodNotImplemented` error mid-session.
      Log.reader.debug("setPreferences: deferred for PDF")
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
      emitReaderStatusChanged(status: ReadiumReaderStatusClosed)
      result(nil)
    default:
      Log.reader.warn("Unhandled call: \(call.method)")
      result(FlutterMethodNotImplemented)
    }
  }
}
