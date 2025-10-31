import Flutter
import Combine
import UIKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

internal var currentPublicationUrlStr: String?
internal var currentPublication: Publication?
internal var currentReaderView: ReadiumReaderView?

func getCurrentPublication() -> Publication? {
  return currentPublication
}

func setCurrentReadiumReaderView(_ readerView: ReadiumReaderView?) {
  currentReaderView = readerView
}

public class FlutterReadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger, TimebasedListener {

  static var registrar: FlutterPluginRegistrar? = nil
  
  /// TTS Decoration style
  internal var ttsUtteranceDecorationStyle: Decoration.Style? = .highlight(tint: .yellow)
  internal var ttsRangeDecorationStyle: Decoration.Style? = .underline(tint: .black)
  
  /// Timebased player events & state
  internal var audioLocatorStreamHandler: EventStreamHandler?
  internal var timebasedPlayerStateStreamHandler: EventStreamHandler?
  internal var lastTimebasedPlayerState: ReadiumTimebasedState? = nil
  
  /// Timebased Navigator. Can be TTS, Audio or MediaOverlay implementations.
  internal var timebasedNavigator: FlutterTimebasedNavigator? = nil
  
  lazy var fallbackChapterTitle: LocalizedString = LocalizedString.localized([
    "en": "Chapter",
    "da": "Kapitel",
    "sv": "Kapitel",
    "no": "Kapittel",
    "is": "Kafli",
  ])

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dk.nota.flutter_readium/main", binaryMessenger: registrar.messenger())
    let instance = FlutterReadiumPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.audioLocatorStreamHandler = EventStreamHandler(withName: "audio-locator", messenger: registrar.messenger())
    instance.timebasedPlayerStateStreamHandler = EventStreamHandler(withName: "timebased-state", messenger: registrar.messenger())
    
    // Register reader view factory
    let factory = ReadiumReaderViewFactory(registrar: registrar)
    registrar.register(factory, withId: readiumReaderViewType)
    
    self.registrar = registrar
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
      self.audioLocatorStreamHandler?.dispose()
      self.audioLocatorStreamHandler = nil
      self.timebasedPlayerStateStreamHandler?.dispose()
      self.timebasedPlayerStateStreamHandler = nil
      result(nil)
    case "closePublication":
      self.closePublication()
      result(nil)
    case "openPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String
      
      Task.detached(priority: .high) {
        do {
          if (currentPublication != nil) {
            self.closePublication()
          }
          let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
          currentPublication = pub
          currentPublicationUrlStr = pubUrlStr
          
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
          let pub: Publication = try await self.loadPublication(fromUrlStr: pubUrlStr).get()
          
          let jsonManifest = pub.jsonManifest
          pub.close()
          
          await MainActor.run {
            result(jsonManifest)
          }
        } catch let err as ReadiumError {
          await MainActor.run {
            result(err.toFlutterError())
          }
        }
      }
    case "getLinkContent":
      let args = call.arguments as! [Any?]
      // TODO: Do we need asString?
      //let asString = args[1] as? Bool ?? true
      let asString = true
      guard let linkStr = args[0] as? String,
            let publication = currentPublication,
            let link = try? Link(fromJsonString: linkStr) else {
        return result(FlutterError.init(
          code: "getLinkContent",
          message: "Failed to get link content",
          details: nil))
      }
      Task.detached(priority: .background) {
        let resource = publication.get(link)
        do {
          if (asString) {
            let linkContent = try await resource?.readAsString(encoding: .utf8).get()
            await MainActor.run {
              result(linkContent)
            }
          } else {
            let data = try await resource!.read().get()
            await MainActor.run {
              result(FlutterStandardTypedData(bytes: data))
            }
          }
        } catch let err {
          await MainActor.run {
            print("\(TAG).getLinkContent exception: \(err)")
            result(
              FlutterError.init(
                code: "getLinkContent",
                message: err.localizedDescription,
                details: "Something went wrong fetching link content."))
          }
        }
      }
      
    case "ttsEnable":
      Task.detached(priority: .high) {
        do {
          let args = call.arguments as? Dictionary<String, Any>,
              ttsPrefs = (try? TTSPreferences(fromMap: args ?? [:])) ?? TTSPreferences()
          //try await self.ttsEnable(withPreferences: ttsPrefs)
          
          guard let publication = getCurrentPublication() else {
            throw ReadiumError.notFound("No publication opened")
          }
          
          Task { @MainActor in
            // Start TTS from the reader's current location
            let currentLocation = currentReaderView?.getCurrentLocation()
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
              code: "TTSEnableFailed",
              message: "Failed to enable TTS: \(error.localizedDescription)",
              details: nil))
          }
        }
      }
    case "ttsGetAvailableVoices":
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
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
      let args = call.arguments as! Dictionary<String, String>
      guard let ttsNavigator = self.timebasedNavigator as? FlutterTTSNavigator else {
        return result(FlutterError.init(
          code: "TTSError",
          message: "TTS Navigator not initialized",
          details: nil))
      }
      do {
        let ttsPrefs = try TTSPreferences(fromMap: args)
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
          locator = await currentReaderView?.getFirstVisibleLocator()
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
              code: "GoToLocator",
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
        else if (currentReaderView != nil) {
          await currentReaderView?.goToLocator(locator: locator, animated: false)
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
          code: "audioEnable",
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
              code: "ArgumentError",
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
            code: "audioSetPreferences",
            message: "AudioNavigator not initialized or Invalid parameters to audioSetPreferences: \(call.arguments.debugDescription)",
            details: nil))
        }
        Task { @MainActor in
          audioNavigator.setAudioPreferences(prefs)
        }
      }
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  public func timebasedNavigator(_: any FlutterTimebasedNavigator, didChangeState state: ReadiumTimebasedState) {
    print(TAG, "TimebasedNavigator state: \(state)")
    timebasedPlayerStateStreamHandler?.sendEvent(state.toJsonString())
  }
  
  public func timebasedNavigator(_: any FlutterTimebasedNavigator, encounteredError error: any Error, withDescription description: String?) {
    print(TAG, "TimebasedNavigator error: \(error), description: \(String(describing: description))")
    // TODO: submit on error stream
  }
  
  public func timebasedNavigator(_: any FlutterTimebasedNavigator, reachedLocator locator: ReadiumShared.Locator, readingOrderLink: ReadiumShared.Link?) {
    print(TAG, "TimebasedNavigator reachedLocator: \(locator), readingOrderLink: \(String(describing: readingOrderLink))")
    
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
    }
  }
}
