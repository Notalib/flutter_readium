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

  /// TTS related variables
  @Published internal var playingUtterance: Locator?
  internal let playingWordRangeSubject = PassthroughSubject<Locator, Never>()
  internal var subscriptions: Set<AnyCancellable> = []
  internal var isMoving = false

  internal var audioLocatorStreamHandler: EventStreamHandler?

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
      // TODO: Implement like this or send with openPublication??
      break
    case "dispose":
      closePublication()
      self.synthesizer?.stop()
      self.synthesizer = nil
      self.audioLocatorStreamHandler?.dispose()
      self.audioLocatorStreamHandler = nil
      result(nil)
    case "closePublication":
      self.closePublication()
      result(nil)
    case "openPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        guard let pub: Publication = await self.loadPublication(fromUrlStr: pubUrlStr, result: result) else {
          // Loading publication failed and should have already called result function with an error.
          // TODO: Consider exception handling on Flutter side, perhaps better to use Result<Publication, OpeningError>
          return
        }
        
        // TODO: Check if a different publication is already open, and close it?
        // TODO: Do any other necessary preloading for a book we're about to read. E.g. for audiobook create AudioNavigator?
        currentPublication = pub

        let jsonManifest = pub.jsonManifest

        await MainActor.run {
          result(jsonManifest)
        }
      }
    case "loadPublication":
      let args = call.arguments as! [Any?]
      let pubUrlStr = args[0] as! String

      Task.detached(priority: .high) {
        guard let pub: Publication = await self.loadPublication(fromUrlStr: pubUrlStr, result: result) else {
          // Loading publication failed and should have already called result function with an error.
          // TODO: Consider exception handling on Flutter side, perhaps better to use Result<Publication, OpeningError>
          return
        }

        let jsonManifest = pub.jsonManifest
        pub.close()

        await MainActor.run {
          result(jsonManifest)
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
      if let locatorStr = args[0] as? String {
        locator = try! Locator(jsonString: locatorStr, warnings: self)!
      }

      Task.detached(priority: .high) {

        if (self.synthesizer != nil) {
          if (locator == nil) {
            locator = await currentReaderView?.getFirstVisibleLocator()
          }
          self.ttsStart(fromLocator: locator)
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
    case "audioEnable":
      guard let args = call.arguments as? [Any?],
            let publication = currentPublication else {
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
        if let locatorStr = args[1] as? String {
          locator = try! Locator(jsonString: locatorStr, warnings: self)!
        }

        if (!publication.conforms(to: Publication.Profile.audiobook)) {
          return result(FlutterError.init(
            code: "audioEnable",
            message: "Book does not conformTo AudioBook: \(call.arguments.debugDescription)",
            details: nil))
        }
        await self.initAudioPlayback(forPublication: publication, withPrefs: prefs, atLocator: locator)

        // TODO: Decide on this, should clients call play after audioEnable?
        self.play()
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
    self.play()
  }

  private func loadPublication (
    fromUrlStr: String,
    result: @escaping FlutterResult
  ) async -> Publication? {
    var pubUrlStr = fromUrlStr
    if (!pubUrlStr.hasPrefix("http") && !pubUrlStr.hasPrefix("file")) {
      // Assume URLs without a supported prefix are local file paths.
      pubUrlStr = "file://\(pubUrlStr)"
    }

    let encodedUrlStr = "\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
    guard let url = URL(string: encodedUrlStr!) else {
      result(FlutterError.init(
        code: "InvalidArgument",
        message: "Invalid publication URL: \(pubUrlStr)",
        details: nil))
      return nil
    }
    guard let absUrl = url.anyURL.absoluteURL else {
      result(FlutterError.init(
        code: "InvalidArgument",
        message: "Invalid publication absoluteURL: \(url.absoluteString)",
        details: nil))
      return nil
    }

    print("Attempting to open publication at: \(absUrl)")
    do {
      let pub: (Publication, Format) = try await self.openPublication(at: absUrl, allowUserInteraction: true, sender: nil)
      let mediaType: String = pub.1.mediaType?.string ?? "unknown"
      print("Opened publication: identifier: \(pub.0.metadata.identifier ?? "[no-ident]") format: \(mediaType)")
      return pub.0
    } catch {
      print("Failed to open publication: \(error)")
      return nil
    }
  }

  private func openPublication(
          at url: AbsoluteURL,
          allowUserInteraction: Bool,
          sender: UIViewController?
      ) async throws -> (Publication, Format) {
          do {
              let asset = try await sharedReadium.assetRetriever!.retrieve(url: url).get()

              let publication = try await sharedReadium.publicationOpener!.open(
                  asset: asset,
                  allowUserInteraction: allowUserInteraction,
                  sender: sender
              ).get()

              return (publication, asset.format)

          } catch {
              throw LibraryError.openFailed(error)
          }
      }

  private func closePublication() {
    // Clean-up any resources associated with the publication.
    currentPublication?.close()
    currentPublication = nil
    synthesizer?.stop()
    synthesizer = nil
    if (audiobookVM != nil) {
      audiobookVM?.navigator.pause()
      audiobookVM = nil
    }
    // Cancel any locator/event subscription jobs
    subscriptions.forEach { job in job.cancel() }
  }
}
