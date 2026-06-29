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
  private var lastSyncLocator: Locator?
  private var lastSyncSegmentDuration: TimeInterval?
  private let publication: Publication
  private var lastViewport: NavigatorViewport?

  /// Runtime narration-sync flag: true = reader follows audio cues (default),
  /// false = manual mode (user took control; audio keeps playing, visual stays put).
  ///
  /// Unified source of truth for sync gating — replaces the direct use of
  /// `preferences?.disableSync` in `syncToLocator`. The flag is initialised from
  /// `preferences.disableSync` when preferences arrive and updated live via
  /// `setNarrationSyncEnabled(_:)` (the method-channel handler) and from manual-mode
  /// detection on page navigation (`goForward`/`goBackward`).
  ///
  /// In-reader user gestures (swipe / edge-tap) are detected in Dart by the
  /// `reader_widget.dart` `Listener` above the platform view, which calls the
  /// reader-view channel `"notifyUserNavigation"` → `enterManualModeIfNarrationPlaying()`.
  /// Those pointer events fire only for genuine user interaction (audio-driven page
  /// turns are programmatic `go(to:)` calls that never reach the Flutter Listener), so
  /// they are a clean "user took control" signal — avoiding the swift-toolkit delegate's
  /// inability to distinguish a finger-swipe from an audio-driven `syncToLocator`.
  private var narrationSyncEnabled: Bool = true

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

    let preferencesMap = creationParams["preferences"] as? Dictionary<String, Any>?
    if let preferencesMap {
      self.preferences = preferencesMap != nil ? FlutterEPUBPreferences.init(fromMap: preferencesMap!) : FlutterEPUBPreferences.init()
    } else {
      Log.reader.debug("No initial preferences map provided")
    }

    let locatorStr = creationParams["initialLocator"] as? String
    // Promote a `#id` css anchor into `fragments.first`: swift-toolkit's reflowable
    // navigator ignores `cssSelector` for initial positioning (unlike kotlin/ts), so a
    // media-overlay locator (DOM anchor in `cssSelector`, audio `t=…` in `fragments`)
    // would otherwise resume at the top of the chapter. See
    // docs/parity/locator-field-priority.md.
    // Parse with `try?` (not `try!`): a malformed / schema-incompatible persisted locator
    // degrades to opening at the start of the publication rather than crashing the reader.
    let locator = locatorStr.flatMap { str -> Locator? in
      guard let parsed = try? Locator(legacyJSONString: str) else {
        Log.reader.warn("Failed to parse initialLocator; opening at start of publication")
        return nil
      }
      return parsed.promotingTextAnchorForVisualNav()
    }
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

    // NOTE: Use experimentalPositioning. It places highlights on z-index -1 behind text, instead of on top.
    var decorationTemplates = HTMLDecorationTemplate.defaultTemplates(alpha: 1.0, experimentalPositioning: true)
    decorationTemplates[Decoration.Style.Id("spotlight")] = EPUBReaderView.spotlightDecorationTemplate()
    config.decorationTemplates = decorationTemplates

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

    // Initialise runtime sync flag from initial preferences so that
    // disableSync:true passed at construction is honoured immediately.
    if let disableSync = self.preferences?.disableSync {
      narrationSyncEnabled = !disableSync
    }

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

    FlutterReadiumPlugin.instance?.registerAsCurrentReaderView(self)

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
    if let preferencesStylesheet = self.preferences.map(effectivePreferences)?.toInjectableStyleSheet() {
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
    // We do note currently see any value in emitting this NavigatorViewport to the client.
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

  /// Resolves preferences against the publication's layout. The first-element top
  /// margin is a reflowable-text affordance, so it's dropped for every non-reflowable
  /// publication — FXL EPUBs and paginated DiViNa report `.fixed`, scrolled DiViNa
  /// reports `.scrolled`, and image publications (CBZ via ImageParser) report no
  /// layout at all — where it would otherwise shift the full-page content down.
  private func effectivePreferences(_ preferences: FlutterEPUBPreferences) -> FlutterEPUBPreferences {
    guard publication.metadata.layout != .reflowable else { return preferences }
    var resolved = preferences
    resolved.firstElementTopMargin = nil
    return resolved
  }

  private func updateCustomPreferences(_ preferences: FlutterEPUBPreferences) {
    let cssVariables = effectivePreferences(preferences).toCustomCssVariables()

    guard cssVariables.isEmpty == false,
          let jsonData = try? jsonEncoder.encode(cssVariables),
          let jsonString = String(data: jsonData, encoding: .utf8) else { return }

    Task.detached(priority: .high) { [jsonString] in
      let result = await self.readiumViewController.evaluateJavaScript("readium.setCSSProperties(\(jsonString));")
      Log.reader.info("updated custom preferences: \(result)")
    }

    // For CBZ/DiViNa FXL publications, also propagate CSS vars to the inner
    // iframe. The FXL wrapper (fxl-spread-one.html) exposes window.spread.eval("", code)
    // which runs JS in the iframe's context. This ensures dynamic preference
    // updates (e.g. toggling B&W mode mid-read) reach the image iframe.
    if publication.conforms(to: Publication.Profile.divina) {
      let innerScript = cssVariables.map { k, v in
        if let v { "document.documentElement.style.setProperty('\(k)','\(v)','important');" }
        else { "document.documentElement.style.removeProperty('\(k)');" }
      }.joined()
      if let scriptData = try? jsonEncoder.encode(innerScript),
         let scriptJson = String(data: scriptData, encoding: .utf8) {
        Task.detached(priority: .high) { [scriptJson] in
          await self.readiumViewController.evaluateJavaScript("window.spread?.eval?.('',\(scriptJson));")
        }
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
        resultLocator.locations.otherLocations["tocHref"] = .string(tocLink.href)
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

    // NOTE: an explicit locator jump (TOC / bookmark / search) during active narration is
    // handled upstream in FlutterReadiumPlugin's "goToLocator" by seeking the timebased
    // navigator (narration follows the jump) — this method is only reached when narration is
    // NOT active, so a jump must not enter manual mode here. Page-turns (goForward/goBackward)
    // do enter manual mode; see those methods.
    isJumpingToLocator = true

    // Promote a `#id` css anchor to `fragments.first` so swift-toolkit positions correctly
    // when jumping to a media-overlay / cssSelector-only locator (e.g. a saved position or
    // bookmark). See docs/parity/locator-field-priority.md.
    let target = locator.promotingTextAnchorForVisualNav()
    return await readiumViewController.go(to: target, options: NavigatorGoOptions(animated: animated))
  }

  public func goToProgression(_ progression: Double, animated: Bool) async -> Bool {
    Log.reader.debug("goToProgression:\(progression)")
    guard let locator = getCurrentLocation() else {
      return false
    }
    let newLocator = locator.copyWithProgressionLocations(progression: progression)
    return await readiumViewController.go(to: newLocator, options: NavigatorGoOptions(animated: animated))
  }


  public func syncToLocator(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval? = nil, isWordRange: Bool = false) async -> Bool {
    if isJumpingToLocator {
      Log.reader.debug("syncToLocator: skipped")
      return false
    }
    if !narrationSyncEnabled {
      lastSyncLocator = locator
      lastSyncSegmentDuration = segmentDuration
      Log.reader.debug("syncToLocator: deferred while narration sync is disabled")
      return false
    }
    // In scroll mode, skip fine-grained word-range syncs. Scrolling to each
    // spoken word re-pins the current paragraph to the top of the viewport
    // ~10×/sec, causing constant snap-to-top jitter. The utterance-level sync
    // and the per-word highlight decoration keep the reader in the right place.
    // In pagination we DO follow the word range, so an utterance spanning a page
    // boundary turns the page to the word currently being spoken.
    if (isWordRange && readiumViewController.presentation.scroll) {
      Log.reader.debug("syncToLocator: skipped word-range sync in scroll mode")
      return false
    }
    // Track the most recent navigated cue so a Re-sync (setNarrationSyncEnabled(true))
    // can snap to the CURRENT cue immediately, even when triggered mid-cue. Previously
    // this was cleared here, so a mid-cue Re-sync had no locator to replay and only
    // corrected once the next cue arrived.
    lastSyncLocator = locator
    lastSyncSegmentDuration = segmentDuration
    return await performSyncNavigation(locator, animated: animated, segmentDuration: segmentDuration)
  }

  private func performSyncNavigation(_ locator: Locator, animated: Bool, segmentDuration: TimeInterval?) async -> Bool {
    Log.reader.debug("syncToLocator: \(locator)")
    if let duration = segmentDuration {
      let segmentDurationMs = duration * 1000.0
      await readiumViewController.evaluateJavaScript("window.flutterReadium.setSegmentDuration(\(segmentDurationMs));");
    }
    // Navigate directly — do NOT call goToLocator, which sets isJumpingToLocator = true.
    // isJumpingToLocator is meant to block TTS syncs while the user/app explicitly navigates
    // (method-channel "go"). Setting it here for a TTS-internal sync causes a cross-page
    // progression stall: the MainActor Task for the next utterance's syncToLocator runs
    // while this Task is suspended awaiting the CSS-column page turn, sees
    // isJumpingToLocator == true, and silently drops the sync. The next utterance then
    // plays audio but the spotlight decoration and page position never advance.
    return await readiumViewController.go(to: locator, options: NavigatorGoOptions(animated: animated))
  }

  /// Sets the runtime narration-sync flag and emits the new state on the
  /// `narration-sync` event channel.
  ///
  /// When enabling sync (true), any deferred sync locator that was held while sync
  /// was disabled is replayed immediately so the visual reader jumps to the current
  /// audio cue.
  ///
  /// Must be called on the MainActor (property access and stream emission are not
  /// thread-safe).
  @MainActor
  internal func setNarrationSyncEnabled(_ enabled: Bool) {
    let wasEnabled = narrationSyncEnabled
    narrationSyncEnabled = enabled
    Log.reader.debug("setNarrationSyncEnabled: \(enabled)")
    FlutterReadiumPlugin.instance?.narrationSyncStreamHandler?.sendEvent(enabled)
    // Replay deferred sync locator when re-enabling, matching the existing
    // wasSyncDisabled catch-up logic that was previously in setPreferences.
    if enabled, !wasEnabled, let deferredLocator = lastSyncLocator {
      let deferredSegmentDuration = lastSyncSegmentDuration
      lastSyncLocator = nil
      lastSyncSegmentDuration = nil
      Task.detached(priority: .high) {
        _ = await self.performSyncNavigation(
          deferredLocator,
          animated: false,
          segmentDuration: deferredSegmentDuration)
      }
    }
  }

  /// Enters manual mode (disables narration sync) if narration is actively
  /// playing. Called from explicit user/app navigation entry points.
  ///
  /// Only transitions when sync is currently enabled and a timebased navigator
  /// is present and playing, so normal reading without narration is unaffected.
  @MainActor
  private func enterManualModeIfNarrationPlaying() {
    guard narrationSyncEnabled,
          FlutterReadiumPlugin.instance?.timebasedNavigator != nil,
          FlutterReadiumPlugin.instance?.lastTimebasedPlayerState?.state == .playing else {
      return
    }
    Log.reader.debug("enterManualModeIfNarrationPlaying: entering manual mode")
    setNarrationSyncEnabled(false)
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
      let args = call.arguments as? [Any?]
      guard let locatorStr = args?[0] as? String,
            let locator = try? Locator(legacyJSONString: locatorStr, warnings: readiumBugLogger) else {
        Log.reader.warn("go: failed to parse locator argument; ignoring navigation request")
        result(false)
        break
      }
      let animated = args?[1] as? Bool ?? false

      Task.detached(priority: .high) {
        let success = await self.goToLocator(locator, animated: animated)
        await MainActor.run() {
          result(success)
        }
      }
      break
    case "goBackward":
      let animated = call.arguments as? Bool ?? false
      let navOptions = NavigatorGoOptions(animated: animated)
      let readiumViewController = self.readiumViewController
      let scrollMode = self.readiumViewController.presentation.scroll

      Task.detached(priority: .high) {
        await MainActor.run { self.enterManualModeIfNarrationPlaying() }
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
      let animated = call.arguments as? Bool ?? false
      let navOptions = NavigatorGoOptions(animated: animated)
      let readiumViewController = self.readiumViewController
      let scrollMode = self.readiumViewController.presentation.scroll

      Task.detached(priority: .high) {
        await MainActor.run { self.enterManualModeIfNarrationPlaying() }
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
    case "notifyUserNavigation":
      // The user swiped or edge-tapped the reader (detected by the Flutter
      // Listener above the platform view). Enter narration manual mode if
      // narration is currently driving the reader; otherwise a no-op.
      Task { @MainActor in
        enterManualModeIfNarrationPlaying()
        result(nil)
      }
      break
    case "setPreferences":
      let args = call.arguments as! [String: Any]
      Log.reader.debug("onMethodCall[setPreferences] args = \(args)")
      let oldDisableSync = self.preferences?.disableSync
      let preferences = FlutterEPUBPreferences.init(fromMap: args)
      setUserPreferences(preferences: preferences)
      self.preferences = preferences
      // Flip the runtime sync flag only on an actual `disableSync` transition.
      // `disableSynchronization` is serialized on every preferences push (non-null on
      // the Dart side), so reacting unconditionally would clobber a manual-mode override
      // set via setNarrationSyncEnabled whenever any unrelated preference (font, theme, …)
      // changes mid-playback.
      if let disableSync = preferences.disableSync, disableSync != oldDisableSync {
        setNarrationSyncEnabled(!disableSync)
      }
      result(nil)
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
      result(nil)
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
      FlutterReadiumPlugin.instance?.clearCurrentReaderView(ifIs: self)
      emitReaderStatusChanged(status: ReadiumReaderStatusClosed)
      result(nil)
      break
    default:
      Log.reader.warn("Unhandled call: \(call.method)")
      result(FlutterMethodNotImplemented)
      break
    }
  }

  /// Loads a bundled Flutter asset's bytes, returning nil (and logging) instead of
  /// trapping when the asset is absent. The webview helper assets
  /// `assets/helpers/flutterReadiumTools.{js,css}` are gitignored build artifacts
  /// (compiled from assets/_helper_scripts/src via `npm run build:flutter` /
  /// `bin/install`); when an app is built without generating them, the reader now
  /// degrades — no helper injection — rather than crashing. See docs/troubleshooting.md.
  private func loadBundledAsset(_ assetKey: String) -> Data? {
    guard let path = Bundle.main.path(forResource: assetKey, ofType: nil) else {
      Log.reader.error("Missing bundled asset '\(assetKey)' — were the webview helpers built? (npm run build:flutter / bin/install)")
      return nil
    }
    guard let data = FileManager().contents(atPath: path) else {
      Log.reader.error("Bundled asset '\(assetKey)' could not be read at \(path)")
      return nil
    }
    return data
  }

  func initUserScripts(registrar: FlutterPluginRegistrar) {
    let flutterReadiumJsKey = registrar.lookupKey(forAsset: "assets/helpers/flutterReadiumTools.js", fromPackage: "flutter_readium")
    let flutterReadiumCssKey = registrar.lookupKey(forAsset: "assets/helpers/flutterReadiumTools.css", fromPackage: "flutter_readium")
    let jsScripts = [flutterReadiumJsKey].compactMap { assetKey -> String? in
      guard let data = loadBundledAsset(assetKey) else { return nil }
      return String(data: data, encoding: .utf8)
    }
    let addCssScripts = [flutterReadiumCssKey].compactMap { assetKey -> String? in
      guard let data = loadBundledAsset(assetKey) else { return nil }
      let base64Css = data.base64EncodedString()
      return """
        (function() {
        var parent = document.getElementsByTagName('head').item(0);
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = window.atob('\(base64Css)');
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

  // MARK: – Custom decoration templates

  /// Escape a string for use as an HTML attribute value (double-quoted).
  private static func escapeHtmlAttr(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
  }

  /// Spotlight: semi-transparent tinted box over the active text range, one per
  /// text line.
  ///
  /// Uses `.boxes` layout (one `<div>` per CSS border box / text line) so that
  /// utterances spanning CSS columns are represented by per-line boxes each
  /// contained within their own column. `.bounds` would produce a single rectangle
  /// spanning the bounding box of the whole range, which overflows across the gutter
  /// and into the next column when an utterance crosses a column boundary.
  ///
  /// The class `flutter-readium-spotlight` is a stable marker that
  /// `flutterReadiumTools.js` watches via MutationObserver to:
  ///   1. Toggle `body.flutter-readium-spotlight-active`, which fades all body text
  ///      to low contrast via an injected CSS rule.
  ///   2. Read `data-css-selector` and add `.flutter-readium-spotlit-text` to the
  ///      matching element, so a higher-specificity CSS rule restores its text colour.
  ///
  /// `background-color` MUST be `!important`: Readium CSS forces every element's
  /// background to transparent when a custom theme is active (see Gotcha in
  /// CLAUDE.md); without `!important` the fill would be invisible.
  ///
  /// `z-index: -1` renders the fill behind the text glyphs (same as the upstream
  /// highlight/underline templates). This keeps the text colour
  /// visually unaffected by the tint overlay and matches what `::highlight()` does
  /// on web — the yellow acts purely as a background, not a colour wash.
  private static func spotlightDecorationTemplate() -> HTMLDecorationTemplate {
    HTMLDecorationTemplate(
      layout: .boxes,
      width: .bounds,
      element: { decoration in
        let config = decoration.style.config as! Decoration.Style.HighlightConfig
        let bgColor = config.tint.map { "\($0.cssValue(alpha: 0.5))" } ?? "transparent"
        let sel = Self.escapeHtmlAttr(decoration.locator.locations.cssSelector ?? "")
        let hl  = Self.escapeHtmlAttr(decoration.locator.text.highlight ?? "")
        let bef = Self.escapeHtmlAttr(decoration.locator.text.before ?? "")
        return "<div class=\"flutter-readium-spotlight\" data-css-selector=\"\(sel)\" data-text-highlight=\"\(hl)\" data-text-before=\"\(bef)\" data-tint=\"\(bgColor)\" style=\"z-index: -1; box-sizing: border-box;\"/>"
      }
    )
  }

}
