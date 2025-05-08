import Flutter
import UIKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin"

private var openedReadiumPublications = [String: Publication]()
private var currentReaderView: ReadiumReaderView?

func getPublicationByIdentifier(_ identifier: String) -> Publication? {
  return openedReadiumPublications[identifier]
}

func setCurrentReadiumReaderView(_ readerView: ReadiumReaderView?) {
  currentReaderView = readerView
}

public class FlutterReadiumPlugin: NSObject, FlutterPlugin, ReadiumShared.WarningLogger {
  static var registrar: FlutterPluginRegistrar? = nil
  
  private var synthesizer: PublicationSpeechSynthesizer? = nil
  private var ttsUtteranceDecoration: Decoration? = nil
  private var ttsRangeDecoration: Decoration? = nil

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dk.nota.flutter_readium/main", binaryMessenger: registrar.messenger())
    let instance = FlutterReadiumPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

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
      // TODO: Implement like this or make an init() or send with openPublication??
      break
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

      Task.detached(priority: .background) {
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
      let args = call.arguments as! [Any?]
      let langCode = args[0] as? String
      let voiceIdentifier = args[1] as? String
      Task.detached(priority: .high) {
        try await self.ttsEnable(withDefaultLangCode: langCode, voiceIdent: voiceIdentifier)
        await MainActor.run {
          result(true)
        }
      }
    case "ttsStart":
      let args = call.arguments as! [Any?]
      var locator: Locator? = nil
      if let locatorStr = args[0] as? String {
        locator = try! Locator(jsonString: locatorStr, warnings: self)!
      }
      
      Task.detached(priority: .background) {
        do {
          try await self.ttsStart(fromLocator: locator)
          await MainActor.run {
            result(true)
          }
        }
        catch {
          await MainActor.run {
            result(FlutterError.init(
              code: "TTSError",
              message: "Failed to start TTS: \(error.localizedDescription)",
              details: nil))
          }
        }
      }
    case "ttsStop":
      self.ttsStop()
      result(true)
    case "ttsPause":
      self.ttsPause()
      result(true)
    case "ttsResume":
      self.ttsResume()
      result(true)
    case "ttsToggle":
      self.ttsPauseOrResume()
      result(true)
    case "ttsNext":
      self.ttsNext()
      result(true)
    case "ttsPrevious":
      self.ttsPrevious()
      result(true)
    case "ttsGetAvailableVoices":
      let availableVocies = self.ttsGetAvailableVoices()
      result(availableVocies.map { $0.jsonString } )
    case "ttsSetVoice":
      let voiceIdentifier = call.arguments as! String
      do {
        try self.ttsSetVoice(voiceIdentifier: voiceIdentifier)
        result(true)
      } catch {
        result(FlutterError.init(
          code: "TTSError",
          message: "Invalid voice identifier: \(error.localizedDescription)",
          details: nil))
      }
    case "ttsSetDecorators":
      let args = call.arguments as! [Any?]
      let rangeDecoration: Decoration
      let uttDecoration: Decoration
      
      if let rangeDecorationStr = args[0] as? String {
        ttsRangeDecoration = try! Decoration(fromJson: rangeDecorationStr)
      }
      if let uttDecorationStr = args[1] as? String {
        ttsUtteranceDecoration = try! Decoration(fromJson: uttDecorationStr)
      }
      result(true)
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
    openedReadiumPublications[pubIdentifier] = nil
  }
}

// MARK: - TTS Implementation

/// Extension handling TTS for ReadiumReaderView
extension FlutterReadiumPlugin : PublicationSpeechSynthesizerDelegate {
  
  func ttsEnable(withDefaultLangCode defaultLangCode: String?, voiceIdent: String?) async throws {
    print(TAG, "ttsEnable")
    try await setupSynthesizerForCurrentPublication(withDefaultLangCode: defaultLangCode, voiceIdent: voiceIdent)
  }
  
  func ttsSetVoice(voiceIdentifier: String) throws {
    print(TAG, "ttsSetVoice: voiceIdent=\(String(describing: voiceIdentifier))")
    
    guard let voice = synthesizer?.voiceWithIdentifier(voiceIdentifier) else {
      throw LibraryError.voiceNotFound
    }
    
    /// Changes are not immediate, they will be applied for the next utterance.
    synthesizer?.config.voiceIdentifier = voiceIdentifier
  }
  
  func ttsStart(fromLocator: Locator?) async throws {
    print(TAG, "ttsStart: fromLocator=\(fromLocator?.jsonString ?? "nil")")
    
    // If no locator provided, start from current visible element.
    var locator = fromLocator
    if (locator == nil) {
      locator = await currentReaderView?.getFirstVisibleLocator()
    }
    self.synthesizer?.start(from: locator)
    
    setupNowPlaying()
  }
  
  func ttsStop() {
    self.synthesizer?.stop()
  }
  
  fileprivate func setupSynthesizerForCurrentPublication(withDefaultLangCode defaultLangCode: String?, voiceIdent: String?) async throws {
    print(TAG, "setupSynthesizer")
    
    guard let ident = await currentReaderView?.publicationIdentifier,
          let publication = openedReadiumPublications[ident] else {
      throw LibraryError.bookNotFound
    }
    
    if (self.synthesizer == nil) {
      self.synthesizer = PublicationSpeechSynthesizer(
        publication: publication,
        config: PublicationSpeechSynthesizer.Configuration(
          defaultLanguage: defaultLangCode != nil ? Language(stringLiteral: defaultLangCode!) : nil,
          voiceIdentifier: voiceIdent,
        )
      )
      self.synthesizer?.delegate = self
    }
  }
  
  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    print(TAG, "publicationSpeechSynthesizerStateDidChange: \(state)")
    var playingUtteranceLocator: Locator? = nil
    var playingRangeLocator: Locator? = nil

    switch state {
    case .playing(let utt, let range):
      playingUtteranceLocator = utt.locator
      playingRangeLocator = range
      if let newLocator = playingUtteranceLocator {
        // TODO: How to handle page turns
        // TODO: this should likely be throttled somewhat
        // See https://github.com/readium/swift-toolkit/blob/master/docs/Guides/TTS.md#turning-pages-automatically
        Task.detached(priority: .high) {
          await currentReaderView?.justGoToLocator(newLocator, animated: false)
        }
      }
      print(TAG, "tts playing: \(utt.text) in \(String(describing: utt.language?.locale.identifier))")
    case .paused(let utt):
      playingUtteranceLocator = utt.locator
      print(TAG, "tts paused at: \(utt.text)")
    case .stopped:
      print(TAG, "tts stopped")
      clearNowPlaying()
    }

    // Update Reader text decorations
    var decorations: [Decoration] = []
    if let locator = playingUtteranceLocator,
       let uttDecoration = ttsUtteranceDecoration {
        decorations.append(uttDecoration)
    }
    if let locator = playingRangeLocator,
       let rangeDecoration = ttsRangeDecoration {
        decorations.append(rangeDecoration)
    }
    currentReaderView?.applyDecorations(decorations, forGroup: "tts")
  }
  
  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    print(TAG, "publicationSpeechSynthesizerUtteranceDidFail: \(error)")
  }
  
  public func ttsPause() {
    self.synthesizer?.pause()
  }
  
  public func ttsResume() {
    self.synthesizer?.resume()
  }
  
  public func ttsPauseOrResume() {
    self.synthesizer?.pauseOrResume()
  }
  
  public func ttsNext() {
    self.synthesizer?.next()
  }
  
  public func ttsPrevious() {
    self.synthesizer?.next()
  }
  
  public func ttsGetAvailableVoices() -> [TTSVoice] {
    return self.synthesizer?.availableVoices ?? []
  }
  
  // MARK: - Now Playing

  // This will display the publication in the Control Center and support
  // external controls.

  private func setupNowPlaying() {
      Task {
        guard let ident = await currentReaderView?.publicationIdentifier,
              let publication = openedReadiumPublications[ident] else {
          throw LibraryError.bookNotFound
        }
          NowPlayingInfo.shared.media = await .init(
              title: publication.metadata.title ?? "",
              artist: publication.metadata.authors.map(\.name).joined(separator: ", "),
              artwork: try? publication.cover().get()
          )
      }

      let commandCenter = MPRemoteCommandCenter.shared()

      commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
          self?.ttsPauseOrResume()
          return .success
      }
  }

  private func clearNowPlaying() {
      NowPlayingInfo.shared.clear()
  }
  
}
