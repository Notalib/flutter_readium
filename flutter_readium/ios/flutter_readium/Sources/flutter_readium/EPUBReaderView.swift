import ReadiumNavigator
import ReadiumShared
import Flutter
import UIKit
import WebKit

private var userScripts: [WKUserScript] = []
private let jsonEncoder = JSONEncoder()

public class EPUBReaderView: NSObject, FlutterPlatformView, ReadiumReaderView, EPUBNavigatorDelegate, VisualNavigatorDelegate, SelectableNavigatorDelegate {

  private let channel: ReadiumReaderChannel
  private let containerView: EPUBContainerView
  private let readiumViewController: EPUBNavigatorViewController
  private var hasSentReady = false
  private var isJumpingToLocator = false
  private var lastHrefLocation: String?
  private var preferences: FlutterEPUBPreferences?
  private let publication: Publication
  private var lastViewport: NavigatorViewport?

  var publicationIdentifier: String?

  public func view() -> UIView {
    Log.reader.debug("getView")
    return containerView
  }

  deinit {
    Log.reader.info("deinit EPUBReaderView")
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
    let locator = locatorStr == nil ? nil : try! Locator(legacyJSONString: locatorStr!)
    let preloadPreviousPositionCount = creationParams["preloadPreviousPositionCount"] as? Int ?? 2
    let preloadNextPositionCount = creationParams["preloadNextPositionCount"] as? Int ?? 6
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
    // Configurable from Flutter via ReadiumReaderWidget. Upstream defaults are
    // 2 previous and 6 next; bumping the "next" count is reasonable for local
    // publications, lowering both helps memory pressure for remote ones.
    config.preloadPreviousPositionCount = preloadPreviousPositionCount
    config.preloadNextPositionCount = preloadNextPositionCount
    config.debugState = false

    // TODO: Use experimentalPositioning for now. It places highlights on z-index -1 behind text, instead of on top.
    config.decorationTemplates = HTMLDecorationTemplate.defaultTemplates(alpha: 1.0, experimentalPositioning: true)

    // TODO: This is a PoC for adding custom editing actions, like user highlights. It should be configurable from Flutter.
    //       See onCustomEditingAction for notes about "catching" this callback on the responder chain.
    //config.editingActions = [.lookup, .translate, EditingAction(title: "Custom Highlight Action", action: #selector(onCustomEditingAction))]

    // Configure selection actions from Flutter creation params.
    let selectionActionsParam = creationParams["selectionActions"] as? [[String: Any]] ?? []
    let allowedDefaultActionsParam = creationParams["allowedDefaultActions"] as? [String]
    let containerView = EPUBContainerView()

    // Build the editing actions list.
    var editingActions: [EditingAction]
    if let allowedDefaults = allowedDefaultActionsParam {
      // Only include explicitly allowed default actions.
      editingActions = []
      for name in allowedDefaults {
        switch name {
        case "copy": editingActions.append(.copy)
        case "share": editingActions.append(.share)
        case "lookup": editingActions.append(.lookup)
        case "translate": editingActions.append(.translate)
        default: break
        }
      }
    } else {
      // null means show all defaults.
      editingActions = EditingAction.defaultActions
    }

    if !selectionActionsParam.isEmpty {
      let actions = selectionActionsParam.compactMap { dict -> (id: String, title: String)? in
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        return (id: id, title: title)
      }
      containerView.configureActions(actions)
      editingActions += containerView.editingActions()
    }

    config.editingActions = editingActions

    if let readiumPreferences = self.preferences?.readium {
      config.preferences = readiumPreferences
    }

    readiumViewController = try! EPUBNavigatorViewController(
      publication: publication,
      initialLocation: locator,
      config: config
    )

    self.containerView = containerView
    super.init()

    containerView.readerView = self
    channel.setMethodCallHandler(onMethodCall)
    readiumViewController.delegate = self

    let child: UIView = readiumViewController.view
    let view = containerView
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

    // Observe decoration interactions for all groups that get applied later.
    // We register a global handler on the well-known "user-highlight" group.
    readiumViewController.observeDecorationInteractions(inGroup: "user-highlight") { [weak self] event in
      self?.onDecorationActivated(event: event)
    }

    Log.reader.debug("init success")
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

  public func navigator(_ navigator: any ViewportObservingNavigator, viewportDidChange viewport: NavigatorViewport?) {
    lastViewport = viewport
    // Re-emit so consumers see updated visible-portion data without waiting
    // for the next locationDidChange (e.g. mid-resource scroll in scroll mode).
    if let locator = readiumViewController.currentLocation {
      emitOnPageChanged(locator: locator)
    }
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

  public func applyDecorations(_ decorations: [Decoration], forGroup groupIdentifier: String) {
    Log.reader.debug("applyDecorations: \(decorations) identifier: \(groupIdentifier)")
    ensureDecorationObservation(forGroup: groupIdentifier)
    self.readiumViewController.apply(decorations: decorations, in: groupIdentifier)
  }

  public func getFirstVisibleLocator() async -> Locator? {
    return await self.readiumViewController.firstVisibleElementLocator()
  }

  public func getCurrentLocation() -> Locator? {
    return self.readiumViewController.currentLocation
  }

  @objc public func onCustomEditingAction() {
    Log.reader.debug("onCustomEditingAction")
    // NOTE: This method will not actually be hit. It will try to find an "onCustomEditingAction" function in the Responder chain!
    // Because of how Flutter generates its responder chain, we need to implement this func in the client AppDelegate.swift and then call back into the plugin from there.
    // see https://github.com/readium/swift-toolkit/issues/466

    if let selection = readiumViewController.currentSelection {
      let selectionLocator = selection.locator
      readiumViewController.apply(decorations: [Decoration(id: "highlight", locator: selectionLocator, style: .highlight(), userInfo: [:])], in: "user-highlight")
      readiumViewController.clearSelection()
    }
  }

  // MARK: - SelectableNavigatorDelegate

  public func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
    Log.reader.debug("shouldShowMenuForSelection: \(selection.locator)")
    let locator = selection.locator
    let selectedText = locator.text.highlight
    channel.onTextSelected(locator: locator, selectedText: selectedText)
    // Return true to also show the native context menu with editing actions.
    return true
  }

  public func navigator(_ navigator: SelectableNavigator, canPerformAction action: EditingAction, for selection: Selection) -> Bool {
    return true
  }

  /// Called by `EPUBContainerView` when a configured action slot fires via the responder chain.
  func handleSelectionAction(actionId: String) {
    Log.reader.debug("handleSelectionAction: \(actionId)")
    guard let selection = readiumViewController.currentSelection else {
      Log.reader.warn("handleSelectionAction: no current selection")
      return
    }
    let locator = selection.locator
    let selectedText = locator.text.highlight
    channel.onSelectionAction(actionId: actionId, locator: locator, selectedText: selectedText)
  }

  func getCurrentSelection() -> Locator? {
    return self.readiumViewController.currentSelection?.locator
  }

  /// Called when a decoration is tapped/activated by the user.
  private func onDecorationActivated(event: OnDecorationActivatedEvent) {
    Log.reader.debug("onDecorationActivated: \(event.decoration.id) in group \(event.group)")
    channel.onDecorationInteraction(
      decorationId: event.decoration.id,
      group: event.group,
      type: "tap",
      locator: event.decoration.locator
    )
  }

  /// Registers decoration interaction observation for a group.
  /// Called when `applyDecorations` is used with a new group identifier.
  private var observedDecorationGroups: Set<String> = ["user-highlight"]
  private func ensureDecorationObservation(forGroup group: String) {
    guard !observedDecorationGroups.contains(group) else { return }
    observedDecorationGroups.insert(group)
    readiumViewController.observeDecorationInteractions(inGroup: group) { [weak self] event in
      self?.onDecorationActivated(event: event)
    }
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

    let viewport = lastViewport

    Task.detached(priority: .high) { [locator, viewport] in
      /// Enrich Locator with PageInformation and ToC.
      var resultLocator = locator
      if let pageInfo = await self.getPageInformation() {
        resultLocator.locations.otherLocations.merge(pageInfo.otherLocations, uniquingKeysWith: { lhs, rhs in lhs })
      }
      if let tocLink = try? await FlutterReadiumPlugin.instance?.currentTocLinkFromLocator(resultLocator) {
        resultLocator.title = tocLink.title
        resultLocator.locations.otherLocations["tocHref"] = .string(tocLink.href)
      }
      if let viewport = viewport {
        // TODO: Decide if we want to use & emit this.
        resultLocator.locations.otherLocations["visibleProgressionStart"] = .double(viewport.progression.lowerBound)
        resultLocator.locations.otherLocations["visibleProgressionEnd"] = .double(viewport.progression.upperBound)
        if let positions = viewport.positions {
          resultLocator.locations.otherLocations["visiblePositionStart"] = .integer(positions.lowerBound)
          resultLocator.locations.otherLocations["visiblePositionEnd"] = .integer(positions.upperBound)
        }
      }

      /// Immutable ref, so that we can use it on the main thread
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

  public func goToLocator(_ locator: Locator, animated: Bool) async -> Bool {
    Log.reader.debug("goToLocator: \(locator)")

    isJumpingToLocator = true

    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  public func goToProgression(_ progression: Double, animated: Bool) async -> Bool {
    Log.reader.debug("goToProgression:\(progression)")
    guard let locator = getCurrentLocation() else {
      return false
    }
    let newLocator = locator.copyWithProgressionLocations(progression: progression)
    return await readiumViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }


  public func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval? = nil) async -> Bool {
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
      let locator = try! Locator(legacyJSONString: args[0] as! String, warnings: readiumBugLogger)!
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
    case "configureSelectionActions":
      let args = call.arguments as! [[String: Any]]
      let actions = args.compactMap { dict -> (id: String, title: String)? in
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        return (id: id, title: title)
      }
      containerView.configureActions(actions)
      result(nil)
      break
    case "dispose":
      Log.reader.info("Disposing readiumViewController")
      readiumViewController.view.removeFromSuperview()
      readiumViewController.delegate = nil
      FlutterReadiumPlugin.instance?.setCurrentReadiumReaderView(nil)
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
