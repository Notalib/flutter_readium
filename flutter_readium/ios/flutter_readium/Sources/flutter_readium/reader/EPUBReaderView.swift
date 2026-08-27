@_spi(ExperimentalTargetElement) import ReadiumNavigator
import ReadiumShared
import Flutter
import UIKit

/// Core class declaration, stored state, lifecycle, and the base `Navigator`/
/// `EPUBNavigatorDelegate` callbacks that don't have a more specific home.
/// Related behaviour lives in the `EPUBReaderView+*.swift` extensions in this
/// directory:
///   - `+Decorations`: applying/observing decorations, custom-highlight action, spotlight template
///   - `+Selection`: `SelectableNavigatorDelegate`, selection-driven actions
///   - `+JSBridge`: injected user scripts, JS evaluation, script-message handling
///   - `+Preferences`: preference application, media-overlay column-break CSS
///   - `+Navigation`: goTo/sync navigation, narration-sync state, scroll-mode paging
///   - `+MethodChannel`: the Flutter method-channel dispatch (`onMethodCall`)
///
/// Stored properties below are `internal` (not `private`) wherever an extension in
/// another file needs them — Swift extensions can only see `private` members of the
/// same type when they live in the same file, and stored properties themselves can
/// only ever be declared here, never added by an extension.
public class EPUBReaderView: NSObject, FlutterPlatformView, ReadiumReaderView, EPUBNavigatorDelegate, VisualNavigatorDelegate, SelectableNavigatorDelegate {

  /// How long locator enrichment (JS page-info + ToC lookup) may take before the raw locator
  /// is emitted instead. Generous for a healthy webview, short enough that a stalled one
  /// doesn't silently freeze the text-locator stream.
  private static let locatorEnrichmentTimeoutSeconds: UInt64 = 5

  let channel: ReadiumReaderChannel
  let containerView: EPUBContainerView
  let readiumViewController: EPUBNavigatorViewController
  private var hasSentReady = false
  var isJumpingToLocator = false
  private var lastHrefLocation: String?
  var isMOActive = false
  var shouldPreventColumnBreaks: Bool { isMOActive && (preferences?.preventMOColumnBreaks ?? true) }
  var preferences: FlutterEPUBPreferences?
  var lastSyncLocator: Locator?
  var lastSyncSegmentDuration: TimeInterval?
  let publication: Publication
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
  var narrationSyncEnabled: Bool = true

  /// Decoration groups currently observed for tap/activation events. Seeded with
  /// "user-highlight" (registered eagerly in `init`); other groups (e.g. the TTS
  /// "timebased-highlight" group) are added lazily by `ensureDecorationObservation`.
  var observedDecorationGroups: Set<String> = ["user-highlight"]

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

    config.fontFamilyDeclarations = Self.customFontFamilyDeclarations(
      from: creationParams["fontFamilyDeclarations"],
      registrar: registrar
    )

    // Readium CSS fixed custom fonts not applying to headings (https://github.com/readium/css/issues/147),
    // but swift-toolkit has not bundled the fix yet. Remove this override once it updates its CSS.
    config.readiumCSSRSProperties.overrides["--RS__compFontFamily"] = "var(--USER__fontFamily, var(--RS__baseFontFamily))"

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
    self.ensureUserScriptsInitialized(registrar: registrar)

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

    // Observe image-tap events via the ExperimentalTargetElement SPI.
    // When the user taps an <img>, the navigator calls back with an
    // ActivateEvent whose targetElement is an ImageContentElement.
    readiumViewController.addObserver(.activate { [weak self] event in
      guard let self = self else { return false }
      guard let imageElement = event.targetElement?.content as? ImageContentElement else {
        return false
      }
      self.onImageTapped(
        image: imageElement,
        frame: event.targetElement?.frame
      )
      return true
    })

    Log.reader.debug("init success")
  }

  private static func customFontFamilyDeclarations(
    from value: Any?,
    registrar: FlutterPluginRegistrar
  ) -> [AnyHTMLFontFamilyDeclaration] {
    guard let families = value as? [[String: Any]] else { return [] }

    return families.compactMap { family in
      guard let name = family["name"] as? String, !name.isEmpty,
            let faceMaps = family["faces"] as? [[String: Any]], !faceMaps.isEmpty else {
        Log.reader.error("Invalid custom font family declaration; skipping family")
        return nil
      }

      let fallbackNames = family["fallbacks"] as? [String] ?? []
      guard fallbackNames.allSatisfy({ !$0.isEmpty }) else {
        Log.reader.error("Invalid custom font fallback in family: \(name)")
        return nil
      }
      let alternates = fallbackNames.map(FontFamily.init(rawValue:))
      let faces = faceMaps.map { face -> CSSFontFace? in
        guard let asset = face["asset"] as? String, !asset.isEmpty,
              let styleName = face["style"] as? String,
              let style = CSSFontStyle(rawValue: styleName),
              let weight = face["weight"] as? Int,
              (1...1000).contains(weight) else {
          Log.reader.error("Invalid custom font face in family: \(name)")
          return nil
        }
        let assetKey = registrar.lookupKey(forAsset: asset)
        guard
              let path = Bundle.main.path(forResource: assetKey, ofType: nil),
              let file = FileURL(path: path, isDirectory: false) else {
          Log.reader.error("Missing custom font asset in family \(name): \(asset)")
          return nil
        }

        let cssWeight: CSSFontWeight
        if let standardWeight = CSSStandardFontWeight(rawValue: weight) {
          cssWeight = .standard(standardWeight)
        } else {
          cssWeight = .variable(weight...weight)
        }
        return CSSFontFace(file: file, style: style, weight: cssWeight)
      }

      guard faces.allSatisfy({ $0 != nil }) else {
        Log.reader.error("Invalid custom font family declaration: \(name)")
        return nil
      }
      return CSSFontFamilyDeclaration(
        fontFamily: FontFamily(rawValue: name),
        alternates: alternates,
        fontFaces: faces.compactMap { $0 }
      ).eraseToAnyHTMLFontFamilyDeclaration()
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

    let payload = FlutterReadiumError(message: error.localizedDescription, code: "ResourceReadError", data: ["href": href.string])
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
      if shouldPreventColumnBreaks {
        injectColumnBreakCSS()
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

  /// Called when the user taps an image element inside an EPUB resource.
  /// Forwards the event to the Flutter channel as an `onImageTapped` call.
  private func onImageTapped(image: ImageContentElement, frame: CGRect?) {
    if suppressesImageTapEvent(image: image) {
      Log.reader.debug("onImageTapped: suppressed for publication/content type")
      return
    }
    Log.reader.debug("onImageTapped: href=\(image.embeddedLink.href)")
    let href = image.embeddedLink.href
    // accessibilityLabel carries the HTML alt="" attribute (stored in attributes
    // under ContentAttributeKey.accessibilityLabel by the HTML content iterator).
    // image.caption is the <figcaption> text — always nil in the current
    // swift-toolkit (see TODO in HTMLResourceContentIterator).
    let alt = image.accessibilityLabel
    channel.onImageTapped(
      href: href,
      alt: alt,
      frame: frame
    )
  }

  private func suppressesImageTapEvent(image: ImageContentElement) -> Bool {
    publication.conforms(to: Publication.Profile.divina)
      || isNotaComicPageImage(image: image)
  }

  private func isNotaComicPageImage(image: ImageContentElement) -> Bool {
    let cssSelector = image.locator.locations.cssSelector ?? ""
    return cssSelector.contains("img.page")
      || cssSelector.contains("#hix")
      || cssSelector.contains(".nota-comicbook-page-container")
  }

  private func emitOnPageChanged(locator: Locator) -> Void {
    Log.reader.debug("emitOnPageChanged, locator: \(locator)")

    Task.detached(priority: .high) { [locator] in
      /// Enrich Locator with PageInformation and ToC — bounded, because upstream's
      /// `EPUBSpreadView.evaluateScript` awaits `spreadLoaded()` with no timeout, so a stalled
      /// webview would freeze this stream forever after `ready` was already reported.
      let enriched = await withTimeout(seconds: Self.locatorEnrichmentTimeoutSeconds) { [locator] in
        var resultLocator = locator
        if let pageInfo = await self.getPageInformation() {
          resultLocator.locations.otherLocations.merge(pageInfo.otherLocations, uniquingKeysWith: { lhs, rhs in lhs })
        }
        if let tocLink = try? await FlutterReadiumPlugin.instance?.currentTocLinkFromLocator(resultLocator) {
          resultLocator.title = tocLink.title
          resultLocator.locations.otherLocations["tocHref"] = .string(tocLink.href)
        }
        return resultLocator
      }

      if enriched == nil {
        Log.reader.warn("emitOnPageChanged: enrichment timed out after \(Self.locatorEnrichmentTimeoutSeconds)s; emitting un-enriched locator")
      }

      /// Immutable ref, so that we can use it on the main thread
      let finalLocator = enriched ?? locator
      await MainActor.run() {
        self.channel.onPageChanged(locator: finalLocator)
        do {
          FlutterReadiumPlugin.instance?.textLocatorStreamHandler?.sendEvent(try finalLocator.jsonString())
        } catch {
          // `try?` used to discard this error, so a serialization failure left no
          // trace anywhere: no event on the stream and nothing in the logs.
          Log.reader.error("Failed to serialize locator for text-locator stream: \(error)")
        }
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

}
