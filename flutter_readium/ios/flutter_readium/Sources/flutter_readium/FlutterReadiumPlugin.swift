import Flutter
import Combine
import UIKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

internal var currentPublication: Publication?
internal var currentReaderView: ReadiumReaderView?

func getCurrentPublication() -> Publication? {
  return currentPublication
}

func setCurrentReadiumReaderView(_ readerView: ReadiumReaderView?) {
  currentReaderView = readerView
}

public class FlutterReadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger {
  static var registrar: FlutterPluginRegistrar? = nil

  /// Audiobook related variables
  internal var audiobookVM: AudiobookViewModel? = nil
  
  internal var mediaOverlays: [FlutterMediaOverlay]? = nil
  internal var lastMediaOverlayItem: FlutterMediaOverlayItem? = nil

  /// TTS related variables
  @Published internal var playingUtterance: Locator?
  internal let playingWordRangeSubject = PassthroughSubject<Locator, Never>()
  internal let playingAudioSubject = PassthroughSubject<Locator, Never>()
  internal var subscriptions: Set<AnyCancellable> = []
  internal var isMoving = false

  internal var audioLocatorStreamHandler: EventStreamHandler?
  internal var timebasedPlayerStateStreamHandler: EventStreamHandler?

  internal var synthesizer: PublicationSpeechSynthesizer? = nil
  internal var ttsPrefs: TTSPreferences? = nil

  // TODO: Should these have defaults?
  internal var ttsUtteranceDecorationStyle: Decoration.Style? = .highlight(tint: .yellow)
  internal var ttsRangeDecorationStyle: Decoration.Style? = .underline(tint: .black)

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
      self.synthesizer?.stop()
      self.synthesizer = nil
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
          try await self.ttsEnable(withPreferences: ttsPrefs)
          await MainActor.run {
            result(nil)
          }
        } catch {
          await MainActor.run {
            result(FlutterError.init(
              code: "TTSEnableFailed",
              message: "Failed to enable TTS: \(error.localizedDescription)",
              details: nil))
          }
        }
      }
    case "ttsGetAvailableVoices":
      let availableVoices = self.ttsGetAvailableVoices()
      result(availableVoices.map { $0.jsonString } )
    case "ttsSetVoice":
      let args = call.arguments as! [Any?]
      let voiceIdentifier = args[0] as! String
      // TODO: language might be supplied as args[1], ignored on iOS for now.
      do {
        try self.ttsSetVoice(voiceIdentifier: voiceIdentifier)
        result(nil)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Invalid voice identifier: \(error.localizedDescription)",
          details: nil))
      }
    case "ttsSetDecorationStyle":
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
      do {
        let ttsPrefs = try TTSPreferences(fromMap: args)
        ttsSetPreferences(prefs: ttsPrefs)
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

        if (self.synthesizer != nil) {
          if (locator == nil) {
            locator = await currentReaderView?.getFirstVisibleLocator()
          }
          self.ttsStart(fromLocator: locator)
        }
        if (locator != nil) {
          await self.audiobookVM?.navigator.go(to: locator!)
        }
        self.audiobookVM?.navigator.play()
        await MainActor.run {
          result(nil)
        }
      }
    case "stop":
      self.audiobookVM?.navigator.pause()
      self.synthesizer?.stop()
      result(nil)
    case "pause":
      self.audiobookVM?.navigator.pause()
      self.synthesizer?.pause()
      result(nil)
    case "resume":
      self.audiobookVM?.navigator.play()
      self.synthesizer?.resume()
      result(nil)
    case "togglePlayback":
      self.audiobookVM?.navigator.playPause()
      self.synthesizer?.pauseOrResume()
      result(nil)
    case "next":
      if (self.audiobookVM != nil) {
        Task {
          // TODO: Configurable seek intervals
          await self.audiobookVM?.navigator.seek(by: 30)
        }
      }
      self.synthesizer?.next()
      result(nil)
    case "previous":
      if (self.audiobookVM != nil) {
        Task {
          // TODO: Configurable seek intervals
          await self.audiobookVM?.navigator.seek(by: -30)
        }
      }
      self.synthesizer?.previous()
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
        if (self.audiobookVM != nil) {
          // TODO: Handle active media-overlay navigator, should map ToC item to audio position
          navigated = await self.audiobookVM!.navigator.go(to: locator)
        }
        if (self.synthesizer != nil) {
          self.synthesizer!.start(from: locator)
          navigated = true
        }
        await MainActor.run { [navigated] in
          result(navigated)
        }
      }
    case "audioEnable":
      guard let args = call.arguments as? [Any?],
            var publication = currentPublication else {
        return result(FlutterError.init(
          code: "audioEnable",
          message: "Invalid parameters to audioEnable: \(call.arguments.debugDescription)",
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
          print("Publication with Synchronized Narration reading-order found!")
          let newPub = await self.openAsMediaOverlayAudiobook(publication)
          // Assign the publication, it should now conform to AudioBook.
          publication = newPub
        }

        if (!publication.conforms(to: Publication.Profile.audiobook)) {
          return result(FlutterError.init(
            code: "ArgumentError",
            message: "Publication does not conformTo AudioBook: \(call.arguments.debugDescription)",
            details: nil))
        }
        await self.initAudioPlayback(forPublication: publication, withPrefs: prefs, atLocator: locator)
        result(nil)
      }
    case "audioSetPreferences":
      guard let prefsMap = call.arguments as? Dictionary<String, Any>,
            let prefs = try? FlutterAudioPreferences.init(fromMap: prefsMap) else {
        return result(FlutterError.init(
          code: "audioSetPreferences",
          message: "Invalid parameters to audioSetPreferences: \(call.arguments.debugDescription)",
          details: nil))
      }
      setAudioPreferences(prefs: prefs)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Extension for handling publication interactions
extension FlutterReadiumPlugin {

  private func initAudioPlayback(
    forPublication publication: Publication,
    withPrefs prefs: FlutterAudioPreferences,
    atLocator locator: Locator?,
  ) async -> Void {
    await self.setupAudiobookNavigator(publication: publication, initialLocator: locator, initialPreferences: prefs)
    // TODO: Should we still auto-play on iOS?
    self.play()
  }
  
  @MainActor
  func syncWithAudioLocator(_ locator: Locator) async -> Bool? {
    return await currentReaderView?.justGoToLocator(locator, animated: false)
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
    synthesizer?.stop()
    synthesizer?.delegate = nil
    synthesizer = nil
    if (audiobookVM != nil) {
      audiobookVM?.navigator.pause()
      audiobookVM?.navigator.delegate = nil
      audiobookVM = nil
    }
    // Cancel any locator/event subscription jobs
    subscriptions.forEach { job in job.cancel() }
    currentPublication?.close()
    currentPublication = nil
  }
}
