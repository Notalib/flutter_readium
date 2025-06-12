import Flutter
import Combine
import UIKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

internal var openedReadiumPublications = Dictionary<String, Publication>()
internal var currentReaderView: ReadiumReaderView?

func getPublicationByIdentifier(_ identifier: String) -> Publication? {
  return openedReadiumPublications[identifier]
}

func setCurrentReadiumReaderView(_ readerView: ReadiumReaderView?) {
  currentReaderView = readerView
}

public class FlutterReadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger {
  static var registrar: FlutterPluginRegistrar? = nil


  /// TTS related variables
  /// TODO: Refactor into a TTSViewModel?
  @Published internal var playingUtterance: Locator?
  internal let playingWordRangeSubject = PassthroughSubject<Locator, Never>()
  internal var subscriptions: Set<AnyCancellable> = []
  internal var isMoving = false

  internal var audioLocatorStreamHandler: EventStreamHandler?

  internal var synthesizer: PublicationSpeechSynthesizer? = nil
  internal var ttsPrefs: TTSPreferences? = nil

  // TODO: Should these have defaults?
  internal var ttsUtteranceDecorationStyle: Decoration.Style? = .highlight(tint: .yellow)
  internal var ttsRangeDecorationStyle: Decoration.Style? = .underline(tint: .red)

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
      openedReadiumPublications.values.forEach { pub in
        pub.close()
      }
      self.synthesizer?.stop()
      self.synthesizer = nil
      self.audioLocatorStreamHandler?.dispose()
      self.audioLocatorStreamHandler = nil
      result(nil)
    case "closePublication":
      let pubId = call.arguments as! String
      self.closePublication(pubId)
      result(nil)
    case "openPublication":
      let args = call.arguments as! [Any?]
      var pubUrlStr = args[0] as! String

      if (!pubUrlStr.hasPrefix("http") && !pubUrlStr.hasPrefix("file")) {
        // Assume URLs without a supported prefix are local file paths.
        pubUrlStr = "file://\(pubUrlStr)"
      }

      let encodedUrlStr = "\(pubUrlStr)".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
      guard let url = URL(string: encodedUrlStr!) else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid publication URL: \(pubUrlStr)",
          details: nil))
      }
      guard let absUrl = url.anyURL.absoluteURL else {
        return result(FlutterError.init(
          code: "InvalidArgument",
          message: "Invalid publication absoluteURL: \(url.absoluteString)",
          details: nil))
      }

      print("Attempting to open publication at: \(absUrl)")

      Task.detached(priority: .high) {
        do {
          let pub: (Publication, Format) = try await self.openPublication(at: absUrl, allowUserInteraction: true, sender: nil)
          let mediaType: String = pub.1.mediaType?.string ?? "unknown"
          print("Opened publication: identifier: \(pub.0.metadata.identifier ?? "[no-ident]") format: \(mediaType)")

          // Save this publication for later use, so we don't have to pass it back across native bridge.
          // TODO: should be set a random identifier if pub doesn't come with any?
          openedReadiumPublications[pub.0.metadata.identifier ?? url.absoluteString] = pub.0

          await MainActor.run {
            result(pub.0.jsonManifest)
          }
        } catch {
            await MainActor.run {
              result(FlutterError.init(
                code: "OpenPublicationError",
                message: "Failed to open publication: \(error.localizedDescription)",
                details: nil))
            }
        }
      }
    case "ttsEnable":
      Task.detached(priority: .high) {
        do {
          let args = call.arguments as! Dictionary<String, Any>,
              ttsPrefs = (try? TTSPreferences(fromMap: args)) ?? TTSPreferences()
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
    case "ttsStart":
      let args = call.arguments as! [Any?]
      var locator: Locator? = nil
      if let locatorStr = args[0] as? String {
        locator = try! Locator(jsonString: locatorStr, warnings: self)!
      }

      Task.detached(priority: .high) {
          if (locator == nil) {
            locator = await currentReaderView?.getFirstVisibleLocator()
          }
          self.ttsStart(fromLocator: locator)
          await MainActor.run {
            result(nil)
          }
      }
    case "ttsStop":
      self.ttsStop()
      result(nil)
    case "ttsPause":
      self.ttsPause()
      result(nil)
    case "ttsResume":
      self.ttsResume()
      result(nil)
    case "ttsToggle":
      self.ttsPauseOrResume()
      result(nil)
    case "ttsNext":
      self.ttsNext()
      result(nil)
    case "ttsPrevious":
      self.ttsPrevious()
      result(nil)
    case "ttsGetAvailableVoices":
      let availableVocies = self.ttsGetAvailableVoices()
      result(availableVocies.map { $0.jsonString } )
    case "ttsSetVoice":
      let voiceIdentifier = call.arguments as! String
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
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Extension for handling publication interactions
extension FlutterReadiumPlugin {

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

  private func closePublication(_ pubIdentifier: String) {
    // Clean-up any resources associated with this publication identifier
    openedReadiumPublications[pubIdentifier]?.close()
    openedReadiumPublications[pubIdentifier] = nil
    synthesizer = nil
  }
}
