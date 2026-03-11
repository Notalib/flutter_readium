import Flutter
import Combine
import UIKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

public class FlutterReadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger, TimebasedListener {

  static var registrar: FlutterPluginRegistrar? = nil
  public static var instance: FlutterReadiumPlugin? = nil

  public var currentPublicationUrlStr: String?
  public var currentPublication: Publication?
  public var currentReaderView: ReadiumReaderView?

  /// TTS Decoration style
  internal var ttsUtteranceDecorationStyle: Decoration.Style? = .highlight(tint: .yellow)
  internal var ttsRangeDecorationStyle: Decoration.Style? = .underline(tint: .black)

  /// General event-stream handlers
  internal var errorStreamHandler: EventStreamHandler?
  internal var readerStatusStreamHandler: EventStreamHandler?
  internal var textLocatorStreamHandler: EventStreamHandler?

  /// Timebased player events & state
  internal var timebasedPlayerStateStreamHandler: EventStreamHandler?
  internal var lastTimebasedPlayerState: ReadiumTimebasedState? = nil

  /// Timebased Navigator. Can be TTS, Audio or MediaOverlay implementations.
  internal var timebasedNavigator: FlutterTimebasedNavigator? = nil

  /// For EPUB profile, maps document path to a list of all the cssSelectors in the document.
  /// This is used to find the current toc item.
  private var currentPublicationCssSelectorMap: [String: [String]]?

  lazy var fallbackChapterTitle: LocalizedString = LocalizedString.localized([
    "en": "Chapter",
    "da": "Kapitel",
    "sv": "Kapitel",
    "no": "Kapittel",
    "is": "Kafli",
  ])

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dk.nota.flutter_readium/main", binaryMessenger: registrar.messenger())

    // Create
    let plugin = FlutterReadiumPlugin()
    registrar.addMethodCallDelegate(plugin, channel: channel)
    plugin.timebasedPlayerStateStreamHandler = EventStreamHandler(withName: "timebased-state", messenger: registrar.messenger())
    plugin.textLocatorStreamHandler = EventStreamHandler(withName: "text-locator", messenger: registrar.messenger())
    plugin.readerStatusStreamHandler = EventStreamHandler(withName: "reader-status", messenger: registrar.messenger())
    plugin.errorStreamHandler = EventStreamHandler(withName: "error", messenger: registrar.messenger())
    instance = plugin

    // Register reader view factory
    let factory = ReadiumReaderViewFactory(registrar: registrar)
    registrar.register(factory, withId: readiumReaderViewType)

    self.registrar = registrar
  }

  internal func getCurrentPublication() -> Publication? {
    return currentPublication
  }

  internal func setCurrentReadiumReaderView(_ readerView: ReadiumReaderView?) {
    currentReaderView = readerView
  }

  public func log(_ warning: Warning) {
    print(TAG, "Error in Readium: \(warning)")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setCustomHeaders":
      guard let args = call.arguments as? [String: Any],
            let httpHeaders = args["httpHeaders"] as? [String: String] else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid custom headers map",
          details: nil))
      }
      sharedReadium.setAdditionalHeaders(httpHeaders)
      result(nil)
    case "dispose":
      closePublication()
      timebasedPlayerStateStreamHandler?.dispose()
      timebasedPlayerStateStreamHandler = nil
      textLocatorStreamHandler?.dispose()
      textLocatorStreamHandler = nil
      readerStatusStreamHandler?.dispose()
      readerStatusStreamHandler = nil
      errorStreamHandler?.dispose()
      errorStreamHandler = nil
      result(nil)
    case "closePublication":
      self.closePublication()
      result(nil)
    case "openPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        do {
          // If Publication is already open, just return it.
          if (self.currentPublicationUrlStr == pubUrlStr) {
            if let jsonManifest = self.currentPublication?.jsonManifest {
              await MainActor.run {
                result(jsonManifest)
              }
            }
          }
          if (self.currentPublication != nil) {
            self.closePublication()
          }
          let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
          self.currentPublication = pub
          self.currentPublicationUrlStr = pubUrlStr

          let jsonManifest = pub.jsonManifest
          await MainActor.run {
            result(jsonManifest)
          }
        } catch let err as ReadiumError {
          await MainActor.run {
            result(err.toFlutterError())
          }
        }
      }
    case "loadPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        do {
          var pubJsonManifest: String?
          if (self.currentPublicationUrlStr == pubUrlStr) {
            /// If Publication is already open, just fetch jsonManifest from current.
            pubJsonManifest = self.currentPublication?.jsonManifest
          } else {
            /// Load Publication and serialize its json manifest, before closing it again.
            let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()

            pubJsonManifest = pub.jsonManifest
            pub.close()
          }

          await MainActor.run { [pubJsonManifest] in
            result(pubJsonManifest)
          }
        } catch let err as ReadiumError {
          await MainActor.run {
            result(err.toFlutterError())
          }
        }
      }
    case "ttsEnable":
      Task.detached(priority: .high) {
        do {
          let args = call.arguments as? Dictionary<String, Any>,
              ttsPrefs = (try? TTSPreferences(fromMap: args ?? [:])) ?? TTSPreferences()

          guard let publication = self.currentPublication else {
            throw ReadiumError.notFound("No publication opened")
          }

          Task { @MainActor in
            // Start TTS from the reader's current location
            let currentLocation = self.currentReaderView?.getCurrentLocation()
            self.timebasedNavigator = FlutterTTSNavigator(publication: publication, preferences: ttsPrefs, initialLocator: currentLocation)
            self.timebasedNavigator?.listener = self
            Task {
              await self.timebasedNavigator?.initNavigator()
            }
            result(nil)
          }
        } catch {
          Task { @MainActor in
            result(FlutterError.init(
              code: "TTSError",
              message: "Failed to enable TTS: \(error.localizedDescription)",
              details: nil))
          }
        }
      }
    case "ttsGetAvailableVoices":
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        result(AVTTSEngine().availableVoices.map { $0.jsonString })
        return
      }
      let availableVoices = ttsNavigator.ttsGetAvailableVoices()
      result(availableVoices.map { $0.jsonString } )
    case "ttsSetVoice":
      let args = call.arguments as! [Any?]
      let voiceIdentifier = args[0] as! String
      // TODO: language might be supplied as args[1], ignored on iOS for now.

      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }

      do {
        try ttsNavigator.ttsSetVoice(voiceIdentifier: voiceIdentifier)
        result(nil)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Invalid voice identifier: \(error.localizedDescription)",
          details: nil))
      }
    case "setDecorationStyle":
      let args = call.arguments as! [Any?]

      if let uttDecorationMap = args[0] as? Dictionary<String, String> {
        ttsUtteranceDecorationStyle = try! Decoration.Style(fromMap: uttDecorationMap)
      }

      if let rangeDecorationMap = args[1] as? Dictionary<String, String> {
        ttsRangeDecorationStyle = try! Decoration.Style(fromMap: rangeDecorationMap)
      }
      result(nil)
    case "ttsSetPreferences":
      let args = call.arguments as? Dictionary<String, Any>
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }
      do {
        let ttsPrefs = try TTSPreferences(fromMap: args!)
        ttsNavigator.ttsSetPreferences(prefs: ttsPrefs)
        result(nil)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Failed to deserialize TTSPreferences: \(error.localizedDescription)",
          details: nil))
      }
    case "play":
      let args = call.arguments as! [Any?]
      var locator: Locator? = nil
      if let locatorJson = args.first as? Dictionary<String, Any> {
        locator = try? Locator(json: locatorJson, warnings: self)
      }

      Task.detached(priority: .high) {
        // If no locator provided, try to start from current ReaderView position.
        if (locator == nil) {
          locator = await self.currentReaderView?.getFirstVisibleLocator()
        }
        await self.timebasedNavigator?.play(fromLocator: locator)

        await MainActor.run {
          result(nil)
        }
      }
    case "stop":
      Task { @MainActor in
        self.timebasedNavigator?.dispose()
        self.timebasedNavigator = nil
        self.updateReaderViewTimebasedDecorations([])
      }
      result(nil)
    case "pause":
      Task { @MainActor in
        await self.timebasedNavigator?.pause()
      }
      result(nil)
    case "resume":
      Task { @MainActor in
        await self.timebasedNavigator?.resume()
      }
      result(nil)
    case "togglePlayback":
      Task { @MainActor in
        await self.timebasedNavigator?.togglePlayPause()
      }
      result(nil)
    case "next":
      Task { @MainActor in
        await self.timebasedNavigator?.seekForward()
      }
      result(nil)
    case "previous":
      Task { @MainActor in
        await self.timebasedNavigator?.seekBackward()
      }
      result(nil)
    case "goToLocator":
      Task.detached(priority: .high) {
        guard let args = call.arguments as? [Any?],
              let locatorJson = args.first as? Dictionary<String, Any>,
              let locator = try? Locator(json: locatorJson, warnings: self)
        else {
          await MainActor.run {
            result(FlutterError.init(
              code: "InvalidArgument",
              message: "Failed to parse locator",
              details: nil))
          }
          return
        }
        var navigated = false

        // Timebased Naviagor seek
        if (self.timebasedNavigator != nil) {
          navigated = await self.timebasedNavigator?.seek(toLocator: locator) ?? false
        }
        // ReaderView goTo
        else if (self.currentReaderView != nil) {
          await self.currentReaderView?.goToLocator(locator: locator, animated: false)
          navigated = true
        }
        await MainActor.run { [navigated] in
          result(navigated)
        }
      }
    case "audioEnable":
      guard let args = call.arguments as? [Any?],
            let publication = currentPublication,
            let pubUrlStr = currentPublicationUrlStr else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "No publication open or Invalid parameters to audioEnable: \(call.arguments.debugDescription)",
          details: nil))
      }
      Task.detached(priority: .high) {
        // Get preferences via arg, or use defaults (empty map).
        let prefsMap = args[0] as? Dictionary<String, Any>,
            prefs = try FlutterAudioPreferences.init(fromMap: prefsMap ?? [:])
        var locator: Locator? = nil
        if let locatorJson = args[1] as? Dictionary<String, Any> {
          locator = try? Locator(json: locatorJson, warnings: self)
        }

        if (publication.containsMediaOverlays) {
          do {
            // MediaOverlayNavigator will modify the Publication readingOrder, so we first load a modifiable copy.
            let modifiablePublicationCopy = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
            await MainActor.run { [locator] in
              self.timebasedNavigator = FlutterMediaOverlayNavigator(publication: modifiablePublicationCopy, preferences: prefs, initialLocator: locator)
            }
          } catch (let err) {
            return result(FlutterError.init(
              code: "Error",
              message: "Failed to reload a modifiable publication copy from: \(pubUrlStr)",
              details: err))
          }
        } else {
          if (!publication.conforms(to: Publication.Profile.audiobook)) {
            return result(FlutterError.init(
              code: "InvalidArgument",
              message: "Publication does not contain MediaOverlays or conforms to AudioBook profile. Args: \(call.arguments.debugDescription)",
              details: nil))
          }
          self.timebasedNavigator = await FlutterAudioNavigator(publication: publication, preferences: prefs, initialLocator: locator)
        }

        self.timebasedNavigator?.listener = self
        await self.timebasedNavigator?.initNavigator()

        await MainActor.run {
          result(nil)
        }
      }
    case "audioSetPreferences":
      Task.detached(priority: .high) {
        guard let audioNavigator = self.timebasedNavigator as? FlutterAudioNavigator,
              let prefsMap = call.arguments as? Dictionary<String, Any>,
              let prefs = try? FlutterAudioPreferences.init(fromMap: prefsMap) else {
          return result(FlutterError.init(
            code: "InvalidArgument",
            message: "AudioNavigator not initialized or Invalid parameters to audioSetPreferences: \(call.arguments.debugDescription)",
            details: nil))
        }
        Task { @MainActor in
          audioNavigator.setAudioPreferences(prefs)
          result(nil)
        }
      }
    case "audioSeekBy":
      Task { @MainActor in
        guard let seekOffset = call.arguments as? Double else {
          return result(FlutterError.init(
            code: "InvalidArgument",
            message: "Invalid parameters to audioSeek: \(call.arguments.debugDescription)",
            details: nil))
        }
        let _ = await self.timebasedNavigator?.seekRelative(byOffsetSeconds: seekOffset)
        result(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, didChangeState state: ReadiumTimebasedState) {
    print(TAG, "TimebasedNavigator state: \(state)")

    Task.detached(priority: .high) {
      // Find and enrich Locator with current ToC link
      if let locator = state.currentLocator,
         let time = locator.locations.time?.begin,
         let pub = self.currentPublication {
        let toc = await pub.getFlattenedToC()
        let flattenedTocForHref = toc.filter {
          $0.hrefPath == locator.href.path
        }
        var matchedTocItem: Link?
        for tocLink in flattenedTocForHref {
          guard let tocTime = tocLink.timeFragmentBegin else {
            continue
          }
          // Save to matchedTocItem, unless timeFromFragment is past time
          if tocTime > time {
            break
          }
          matchedTocItem = tocLink
        }
        if let tocLinkHref = matchedTocItem?.href {
          print(TAG, "Found matching TOC item: \(tocLinkHref)")
          state.currentLocator?.locations.otherLocations["toc"] = tocLinkHref
        }
      }
      Task { @MainActor [state] in
        self.timebasedPlayerStateStreamHandler?.sendEvent(state.toJsonString())
      }
    }
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, encounteredError error: any Error, withDescription description: String?) {
    print(TAG, "TimebasedNavigator error: \(error), description: \(String(describing: description))")
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(FlutterReadiumError(message: error.localizedDescription, code: "TimeBasedNavigatorError", data: description))
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, reachedLocator locator: ReadiumShared.Locator) {
    print(TAG, "TimebasedNavigator reachedLocator: \(locator)")

    Task { @MainActor [locator] in
      await currentReaderView?.goToLocator(locator: locator, animated: false)
    }
  }

  public func timebasedNavigator(_: any FlutterTimebasedNavigator, requestsHighlightAt locator: ReadiumShared.Locator?, withWordLocator wordLocator: ReadiumShared.Locator?) {
    print(TAG, "TimebasedNavigator requestsHighlightAt: \(String(describing: locator)), withWordLocator: \(String(describing: wordLocator))")

    // Update Reader text decorations
    var decorations: [Decoration] = []
    if let uttLocator = locator,
       let uttDecorationStyle = ttsUtteranceDecorationStyle {
      decorations.append(Decoration(
        id: "tts-utt", locator: uttLocator, style: uttDecorationStyle
      ))
    }
    if let rangeLocator = wordLocator,
       let rangeDecorationStyle = ttsRangeDecorationStyle {
      decorations.append(Decoration(
        id: "tts-range", locator: rangeLocator, style: rangeDecorationStyle
      ))
    }
    Task { @MainActor [decorations] in
      updateReaderViewTimebasedDecorations(decorations)
    }
  }
}

/// Extension for handling publication interactions
extension FlutterReadiumPlugin {

  @MainActor
  func updateReaderViewTimebasedDecorations(_ decorations: [Decoration]) {
    currentReaderView?.applyDecorations(decorations, forGroup: "timebased-highlight")
  }

  func clearNowPlaying() {
    NowPlayingInfo.shared.clear()
  }

  private func loadPublication (
    fromUrlStr: String,
  ) async -> Result<Publication, ReadiumError> {
    var pubUrlStr = fromUrlStr
    if (!pubUrlStr.hasPrefix("http") && !pubUrlStr.hasPrefix("file")) {
      // Assume URLs without a supported prefix are local file paths.
      pubUrlStr = "file://\(pubUrlStr)"
    }

    let encodedUrlStr = "\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    guard let url = URL(string: encodedUrlStr!) else {
      return .failure(ReadiumError.notFound("Invalid pub URL: \(pubUrlStr)"))
    }
    guard let absUrl = url.anyURL.absoluteURL else {
      return .failure(ReadiumError.notFound("Failed to get AbsoluteUrl: \(pubUrlStr)"))
    }

    print("Attempting to open publication at: \(absUrl)")
    do {
      let pub: (Publication, Format) = try await self.openPublication(at: absUrl, allowUserInteraction: true, sender: nil)
      let mediaType: String = pub.1.mediaType?.string ?? "unknown"
      print("Opened publication: identifier: \(pub.0.metadata.identifier ?? "[no-ident]") format: \(mediaType)")
      return .success(pub.0)
    } catch let error {
      print("Failed to open publication: \(error)")
      return .failure(error)
    }
  }

  private func openPublication(
    at url: AbsoluteURL,
    allowUserInteraction: Bool,
    sender: UIViewController?
  ) async throws(ReadiumError) -> (Publication, Format) {
    do {
      let asset = try await sharedReadium.assetRetriever!.retrieve(url: url).get()

      let publication = try await sharedReadium.publicationOpener!.open(
        asset: asset,
        allowUserInteraction: allowUserInteraction,
        sender: sender
      ).get()

      return (publication, asset.format)
    } catch let err {
      throw err.toReadiumError()
    }
  }

  private func closePublication() {
    // Clean-up any resources associated with the publication.
    Task { @MainActor in
      self.timebasedNavigator?.dispose()
      self.timebasedNavigator = nil
      currentPublication?.close()
      currentPublication = nil
      currentPublicationUrlStr = nil
      currentPublicationCssSelectorMap = [:]
    }
  }
}

/// Extension for finding current ToC location
extension FlutterReadiumPlugin {

  /// Find the current table of content item from a locator.
  func currentTocLinkFromLocator(_ locator: Locator) async throws -> Link? {
    guard let publication = currentPublication else {
      debugPrint(TAG, ":currentTocLinkFromLocator, no currentPublication")
      return nil
    }

    guard let cssSelector = await publication.findCssSelectorForLocator(locator: locator) else {
      debugPrint(TAG, ":epubFindCurrentToc, could not find cssSelector from locator")
      return nil
    }

    let cleanHrefPath = locator.href.path

    let contentIds = try await epubGetAllDocumentCssSelectors(hrefPath: cleanHrefPath)

    var idx = contentIds.firstIndex(of: cssSelector)
    if idx == nil {
      debugPrint(TAG, ":currentTocLinkFromLocator cssSelector:\(cssSelector) not found in current href, assuming 0")
      idx = 0
    }

    let toc = Dictionary(
      uniqueKeysWithValues:
        await publication.getFlattenedToC()
        .filter { RelativeURL(epubHREF: $0.href)?.path == cleanHrefPath }
        .compactMap { item -> (Int, Link)? in
          let fragment = RelativeURL(epubHREF: item.href)?.fragment ?? ""
          guard let index = contentIds.firstIndex(of: "#\(fragment)") else { return nil }
          return (index, item)
        }
    )

    let tocItem = (toc.filter { $0.key <= idx! }
                     .sorted { $0.key < $1.key }
                     .last?.value
    ?? toc.sorted { $0.key < $1.key }.first?.value)
    return tocItem
  }

  /// Get all cssSelectors for an EPUB file.
  func epubGetAllDocumentCssSelectors(hrefPath: String) async throws -> [String] {
    if currentPublicationCssSelectorMap == nil {
      currentPublicationCssSelectorMap = [:]
    }

    if let cached = currentPublicationCssSelectorMap?[hrefPath] {
      return cached
    }

    let selectors = await currentPublication?.findAllCssSelectors(hrefRelativePath: hrefPath) ?? []

    currentPublicationCssSelectorMap?[hrefPath] = selectors
    return selectors
  }
}
