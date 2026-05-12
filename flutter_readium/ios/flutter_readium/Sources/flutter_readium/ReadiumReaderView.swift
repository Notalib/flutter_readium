import ReadiumNavigator
import ReadiumAdapterGCDWebServer
import ReadiumShared
import Flutter
import UIKit
import WebKit

private let ReadiumReaderStatusReady = "ready"
private let ReadiumReaderStatusLoading = "loading"
private let ReadiumReaderStatusClosed = "closed"
private let ReadiumReaderStatusError = "error"

let readiumReaderViewType = "dk.nota.flutter_readium/ReadiumReaderWidget"

class ReadiumBugLogger: ReadiumShared.WarningLogger {
  func log(_ warning: Warning) {
    Log.reader.error("Error in Readium while deserializing: \(warning)")
  }
}

private let readiumBugLogger = ReadiumBugLogger()
private var userScripts: [WKUserScript] = []
private let jsonEncoder = JSONEncoder()

private func emitReaderStatusChanged(status: String) {
  if let jsonData = try? jsonEncoder.encode(status),
     let jsonString = String(data: jsonData, encoding: .utf8) {
    FlutterReadiumPlugin.instance?.readerStatusStreamHandler?.sendEvent(jsonString)
  }
}

public class ReadiumReaderView: NSObject, FlutterPlatformView, EPUBNavigatorDelegate, VisualNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private let _view: UIView
  private let readiumViewController: EPUBNavigatorViewController
  private var hasSentReady = false
  private var isJumpingToLocator = false
  private var lastHrefLocation: String?
  private var preferences: FlutterEPUBPreferences?
  private let publication: Publication

  var publicationIdentifier: String?

  public func view() -> UIView {
    Log.reader.debug("getView")
    return _view
  }

  deinit {
    Log.reader.info("dispose")
    readiumViewController.view.removeFromSuperview()
    readiumViewController.delegate = nil
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

    let preferencesMap = creationParams["preferences"] as? Dictionary<String, Any>?
    self.preferences = preferencesMap == nil ? FlutterEPUBPreferences.init() : FlutterEPUBPreferences.init(fromMap: preferencesMap!!)

    let locatorStr = creationParams["initialLocator"] as? String
    let locator = locatorStr == nil ? nil : try! Locator.init(jsonString: locatorStr!)
    Log.reader.debug("publication = \(publication)")

    channel = ReadiumReaderChannel(
      name: "\(readiumReaderViewType):\(viewId)", binaryMessenger: registrar.messenger())

    emitReaderStatusChanged(status: ReadiumReaderStatusLoading)

    Log.reader.info("Publication: (identifier=\(String(describing: publication.metadata.identifier)),title=\(String(describing: publication.metadata.title)))")
    Log.reader.info("Added publication at \(String(describing: publication.baseURL))")

    // Remove undocumented Readium default 20dp or 44dp top/bottom padding.
    // See EPUBNavigatorViewController.swift in r2-navigator-swift.
    var config = EPUBNavigatorViewController.Configuration()

    // TODO: Use config.readiumCSSRSProperties.overrides to add custom CSS variables
    //config.readiumCSSRSProperties.overrides = [:]

    config.contentInset = [
      .compact: (top: 0, bottom: 0),
      .regular: (top: 0, bottom: 0),
    ]
    // TODO: Make this config configurable from Flutter
    // Might want it to be higher for a local publication than remote. Default is 2 previous and 6 next resources.
    config.preloadPreviousPositionCount = 2
    config.preloadNextPositionCount = 4
    config.debugState = false

    // TODO: Use experimentalPositioning for now. It places highlights on z-index -1 behind text, instead of on top.
    config.decorationTemplates = HTMLDecorationTemplate.defaultTemplates(alpha: 1.0, experimentalPositioning: true)

    // TODO: This is a PoC for adding custom editing actions, like user highlights. It should be configurable from Flutter.
    //       See onCustomEditingAction for notes about "catching" this callback on the responder chain.
    //config.editingActions = [.lookup, .translate, EditingAction(title: "Custom Highlight Action", action: #selector(onCustomEditingAction))]

    if let readiumPreferences = self.preferences?.readium {
      config.preferences = readiumPreferences
    }

    readiumViewController = try! EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config,
      httpServer: sharedReadium.httpServer!
    )

    _view = UIView()
    super.init()

    channel.setMethodCallHandler(onMethodCall)
    readiumViewController.delegate = self

    let child: UIView = readiumViewController.view
    let view = _view
    view.addSubview(readiumViewController.view)

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

    /// Ensure userScripts are initialized for later injection.
    if userScripts.isEmpty {
      self.initUserScripts(registrar: registrar)
    }

    /// This adapter will automatically turn pages when the user taps the
    /// screen edges or presses arrow keys.
    DirectionalNavigationAdapter(
      pointerPolicy: .init(types: [.mouse, .touch])
    ).bind(to: readiumViewController)

    Log.reader.debug("init success")
  }

  @objc public func onCustomEditingAction() {
    Log.reader.debug("EditingAction::NOTA")
    // NOTE: This method will not actually be hit. It will try to find an "onCustomEditingAction" function in the Responder chain!
    // Because of how Flutter generates its responder chain, we need to implement this func in the client AppDelegate.swift and then call back into the plugin from there.
    // see https://github.com/readium/swift-toolkit/issues/466

    if let selection = readiumViewController.currentSelection {
      let selectionLocator = selection.locator
      readiumViewController.apply(decorations: [Decoration(id: "highlight", locator: selectionLocator, style: .highlight(), userInfo: [:])], in: "user-highlight")
      readiumViewController.clearSelection()
    }
  }

  // implements EPUBNavigatorDelegate::navigator:setupUserScripts
  public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
    Log.reader.debug("setupUserScripts: adding \(userScripts.count) scripts")
    for script in userScripts {
      userContentController.addUserScript(script)
    }

    /// Custom preferences added dynamically for each WebView, to make sure changes to preferences are respected.
    if let preferencesStylesheet = self.preferences?.toInjectableStyleSheet() {
      let source = """
        (function() {
        var parent = document.getElementsByTagName('head').item(0);
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = '\(preferencesStylesheet)';
        parent.appendChild(style)})();
      """
      userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
  }

  func middleTapHandler() {
    Log.reader.debug("EPUBNavigatorDelegate.middleTapHandler")
  }

  public func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
    // All margin & safe-area is handled on the Flutter side.
    return .init(top: 0, left: 0, bottom: 0, right: 0)
  }

  // implements EPUBNavigatorDelegate::navigator:presentError
  public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    Log.reader.error("Should present error: \(error)")
  }

  // implements EPUBNavigatorDelegate::navigator:didFailToLoadResourceAt
  public func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    Log.reader.warn("didFailToLoadResourceAt: \(href). err: \(error)")

    // TODO: Should we send resource-load error like this?
    emitReaderStatusChanged(status: ReadiumReaderStatusError)

    let payload = FlutterReadiumError(message: error.localizedDescription, code: "DidFailToLoadResource", data: href.string)
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(payload.toJsonString())
  }
  
  public func navigator(_ navigator: any Navigator, didJumpTo locator: Locator) {
    Log.reader.debug("didJumpTo: \(locator)")
    isJumpingToLocator = false
  }

  // implements NavigatorDelegate::navigator:locationDidChange
  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    Log.reader.debug("onPageChanged: \(locator)")
    if (!hasSentReady) {
      emitReaderStatusChanged(status: ReadiumReaderStatusReady)
      hasSentReady = true
    }
    if (lastHrefLocation != locator.href.string) {
      lastHrefLocation = locator.href.string
      /// Ensure that custom preference CSS variables are set, when changing resources.
      if let preferences = self.preferences {
        updateCustomPreferences(preferences)
      }
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

  /// Called when the user taps on a link referring to a note.
  ///
  /// Return `true` to navigate to the note, or `false` if you intend to present the
  /// note yourself, using its `content`. `link.type` contains information about the
  /// format of `content` and `referrer`, such as `text/html`.
  public func navigator(_ navigator: Navigator, shouldNavigateToNoteAt link: Link, content: String, referrer: String?) -> Bool {
    Log.reader.info("user tapped on note: \(content)")
    return true
  }

  func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    Log.reader.debug("applyDecorations: \(decorations) identifier: \(groupIdentifier)")
    self.readiumViewController.apply(decorations: decorations, in: groupIdentifier)
  }

  func getFirstVisibleLocator() async -> Locator? {
    return await self.readiumViewController.firstVisibleElementLocator()
  }

  func getCurrentLocation() -> Locator? {
    return self.readiumViewController.currentLocation
  }

  func getCurrentSelection() -> Locator? {
    return self.readiumViewController.currentSelection?.locator
  }

  private func evaluateJavascript(_ code: String) async -> Result<Any, Error> {
    return await self.readiumViewController.evaluateJavaScript(code)
  }

  private func evaluateJSReturnResult(_ code: String, result: @escaping FlutterResult) {
    Task.detached(priority: .high) {
      do {
        let data = try await self.evaluateJavascript(code).get()
        Log.reader.debug("evaluateJavascript result: \(data)")
        await MainActor.run() {
          return result(data)
        }
      } catch (let err) {
        Log.reader.error("evaluateJavascript error: \(err)")
        await MainActor.run() {
          return result(nil)
        }
      }
    }
  }

  private func setUserPreferences(preferences: FlutterEPUBPreferences) {
    self.readiumViewController.submitPreferences(preferences.readium)
    self.updateCustomPreferences(preferences)
  }

  private func updateCustomPreferences(_ preferences: FlutterEPUBPreferences) {
    let cssVariables = preferences.toCustomCssVariables()
    if cssVariables.isEmpty == false,
       let jsonData = try? jsonEncoder.encode(cssVariables),
       let jsonString = String(data: jsonData, encoding: .utf8) {
      Task.detached(priority: .high) { [jsonString] in
        let result = await self.readiumViewController.evaluateJavaScript("readium.setCSSProperties(\(jsonString));")
        Log.reader.info("updated custom preferences: \(result)")
      }
    }
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    Log.reader.debug("emitOnPageChanged, locator: \(locator)")

    Task.detached(priority: .high) { [locator] in
      /// Enrich Locator with PageInformation and ToC.
      var resultLocator = locator
      if let pageInfo = await self.getPageInformation() {
        resultLocator.locations.otherLocations.merge(pageInfo.otherLocations, uniquingKeysWith: { lhs, rhs in lhs })
      }
      if let tocLink = try? await FlutterReadiumPlugin.instance?.currentTocLinkFromLocator(resultLocator) {
        resultLocator.title = tocLink.title
        resultLocator.locations.otherLocations["tocHref"] = tocLink.href
      }

      /// Immutable ref, so that we can use it on the main thread
      let finalLocator = resultLocator
      await MainActor.run() {
        self.channel.onPageChanged(locator: finalLocator)
        FlutterReadiumPlugin.instance?.textLocatorStreamHandler?.sendEvent(finalLocator.jsonString)
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

  internal func getPageInformation() async -> PageInformation? {
    switch await self.evaluateJavascript("window.flutterReadium.getPageInformation();") {
    case .success(let jresult):
      let pageInfo = PageInformation.fromJson(jresult as? Dictionary<String, Any> ?? Dictionary())
      return pageInfo
    case .failure(let err):
      Log.reader.error("getPageInformation failed! \(err)")
      return nil
    }
  }

  func goToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    Log.reader.debug("goToLocator: \(locator)")
    
    isJumpingToLocator = true

    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  func goToProgression(_ progression: Double, animated: Bool) async -> Bool {
    Log.reader.debug("goToProgression:\(progression)")
    guard let locator = getCurrentLocation() else {
      return false
    }
    let newLocator = locator.copyWithProgressionLocations(progression: progression)
    return await readiumViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }


  func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval? = nil) async -> Bool {
    if (isJumpingToLocator || preferences?.disableSync == true) {
      Log.reader.debug("syncToLocator: skipped")
      return false
    }
    Log.reader.debug("syncToLocator: \(locator)")
    if let duration = segmentDuration {
      let segmentDurationMs = duration * 1000.0
      await readiumViewController.evaluateJavaScript("window.flutterReadium.setSegmentDuration(\(segmentDurationMs));");
    }
    return await goToLocator(locator, animated: animated)
  }

  private func emitOnPageChanged() {
    guard let locator = readiumViewController.currentLocation else {
      Log.reader.warn("emitOnPageChanged: currentLocation was nil!")
      return
    }

    navigator(readiumViewController, locationDidChange: locator)
  }

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
      break
    case "goBackward":
      let animated = call.arguments as! Bool
      let navOptions = NavigatorGoOptions(animated: animated)
      let readiumViewController = self.readiumViewController
      let scrollMode = self.readiumViewController.presentation.scroll

      Task.detached(priority: .high) {
        let layoutMode = await self.readiumViewController.publication.metadata.layout ?? Layout.reflowable
        let success: Bool
        if (layoutMode == .reflowable && scrollMode == true) {
          success = await self.goBackwardInScrollMode(options: navOptions)
        } else {
          success = await readiumViewController.goBackward(options: navOptions)
        }
        await MainActor.run() {
          result(success)
        }
      }
      break
    case "goForward":
      let animated = call.arguments as! Bool
      let navOptions = NavigatorGoOptions(animated: animated)
      let readiumViewController = self.readiumViewController
      let scrollMode = self.readiumViewController.presentation.scroll

      Task.detached(priority: .high) {
        let layoutMode = await self.readiumViewController.publication.metadata.layout ?? Layout.reflowable
        let success: Bool
        if (layoutMode == .reflowable && scrollMode == true) {
          success = await self.goForwardInScrollMode(options: navOptions)
        } else {
          success = await readiumViewController.goForward(options: navOptions)
        }
        await MainActor.run() {
          result(success)
        }
      }
      break
    case "setPreferences":
      let args = call.arguments as! [String: Any]
      Log.reader.debug("onMethodCall[setPreferences] args = \(args)")
      let preferences = FlutterEPUBPreferences.init(fromMap: args)
      setUserPreferences(preferences: preferences)
      self.preferences = preferences
      break
    case "applyDecorations":
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
      break
    case "dispose":
      Log.reader.info("Disposing readiumViewController")
      readiumViewController.view.removeFromSuperview()
      readiumViewController.delegate = nil
      emitReaderStatusChanged(status: ReadiumReaderStatusClosed)
      result(nil)
      break
    default:
      Log.reader.warn("Unhandled call: \(call.method)")
      result(FlutterMethodNotImplemented)
      break
    }
  }

  func initUserScripts(registrar: FlutterPluginRegistrar) {
    let flutterReadiumJsKey = registrar.lookupKey(forAsset: "assets/helpers/flutterReadiumTools.js", fromPackage: "flutter_readium")
    let flutterReadiumCssKey = registrar.lookupKey(forAsset: "assets/helpers/flutterReadiumTools.css", fromPackage: "flutter_readium")
    let jsScripts = [flutterReadiumJsKey].map { sourceFile -> String in
      let path = Bundle.main.path(forResource: sourceFile, ofType: nil)!
      let data = FileManager().contents(atPath: path)!
      return String(data: data, encoding: .utf8)!
    }
    let addCssScripts = [flutterReadiumCssKey].map { sourceFile -> String in
      let path = Bundle.main.path(forResource: sourceFile, ofType: nil)!
      let data = FileManager().contents(atPath: path)!.base64EncodedString()
      return """
        (function() {
        var parent = document.getElementsByTagName('head').item(0);
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = window.atob('\(data)');
        parent.appendChild(style)})();
      """
    }

    /// INJECTED AT DOCUMENT START

    /// Add JS scripts right away, before loading the rest of the document.
    for jsScript in jsScripts {
      userScripts.append(WKUserScript(source: jsScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }
    /// Add simple script used by our JS to detect OS
    userScripts.append(WKUserScript(source: "const isAndroid=false,isIos=true;", injectionTime: .atDocumentStart, forMainFrameOnly: false))

    /// Add all known ToC IDs for this publication to a global javascript array.
    do {
      let tocFragments = self.readiumViewController.publication.getFlattenedToC().compactMap(\.fragment)
      let data = try jsonEncoder.encode(tocFragments)
      if let tocFragmentsJSON = String(data: data, encoding: String.Encoding.utf8) {
        let tocScript = "window.readiumTocIDs = \(tocFragmentsJSON);"
        userScripts.append(WKUserScript(source: tocScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
      }
    } catch (let err) {
      Log.readium.error("Failed to inject ToC IDs in webview: \(err)")
    }

    /// INJECTED AT DOCUMENT END

    /// Add css injection scripts after primary document finished loading.
    for addCssScript in addCssScripts {
      userScripts.append(WKUserScript(source: addCssScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
  }

  func goBackwardInScrollMode(options: NavigatorGoOptions) async -> Bool {
    guard var locator = getCurrentLocation(),
          let currentProgression = locator.locations.progression else {
      Log.reader.error("no current location or progression")
      return false
    }
    let jsResult = await self.evaluateJavascript("window.flutterReadium.getViewPortSize();")
    guard case .success(let viewPortResult) = jsResult,
          let viewPortMap = viewPortResult as? Dictionary<String, Any> else {
      Log.reader.error("getViewPortSize JS eval failed – \(jsResult.getOrNil() ?? "nil")")
      return false
    }
    let viewPort = ViewPortSize.fromJson(viewPortMap, scrollMode: true)
    let progression = viewPort.progression
    let prevProgression = viewPort.prevProgression
    if (progression == 0.0 && prevProgression <= 0.0) {
      // Current progress is already at the top and prevProgression is <= 0.0,
      // We need to go to the previous file in the readingOrder.
      Log.reader.debug("at beginning, use default goBackward")
      return await self.readiumViewController.goBackward(options: options)
    }

    Log.reader.debug("goBackward from progression:\(currentProgression) to \(prevProgression)")
    locator.locations.progression = clamp(prevProgression, minValue: 0.0, maxValue: 1.0)
    return await self.readiumViewController.go(to: locator, options: options)
  }

  func goForwardInScrollMode(options: NavigatorGoOptions) async -> Bool {
    guard var locator = getCurrentLocation(),
          let currentProgression = locator.locations.progression else {
      Log.reader.error("no current location or progression")
      return false
    }
    let jsResult = await self.evaluateJavascript("window.flutterReadium.getViewPortSize();")
    guard case .success(let viewPortResult) = jsResult,
          let viewPortMap = viewPortResult as? Dictionary<String, Any> else {
      Log.reader.error("getViewPortSize JS eval failed – \(jsResult.getOrNil() ?? "nil")")
      return false
    }
    let viewPort = ViewPortSize.fromJson(viewPortMap, scrollMode: true)

    let endProgression = viewPort.endProgression
    let nextProgression = viewPort.nextProgression
    if (nextProgression >= 1.0 && endProgression == 1.0) {
      // Current progress is already at the top and prevProgression is <= 0.0,
      // We need to go to the previous file in the readingOrder.
      Log.reader.debug("at end, use default goForward")
      return await self.readiumViewController.goForward(options: options)
    }

    Log.reader.debug("goForward from progression:\(currentProgression) to \(nextProgression)")
    locator.locations.progression = clamp(nextProgression, minValue: 0.0, maxValue: 1.0)
    return await self.readiumViewController.go(to: locator, options: options)
  }
}
