import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin/TTS"

extension FlutterReadiumPlugin : PublicationSpeechSynthesizerDelegate, AVTTSEngineDelegate {
  
  fileprivate func setupSynthesizer(withPreferences prefs: TTSPreferences?) async throws {
    print(TAG, "setupSynthesizer")
    
    var engine: AVTTSEngine?

    guard let ident = await currentReaderView?.publicationIdentifier,
          let publication = openedReadiumPublications[ident] else {
      throw LibraryError.bookNotFound
    }

    self.synthesizer = PublicationSpeechSynthesizer(
      publication: publication,
      config: PublicationSpeechSynthesizer.Configuration(
          defaultLanguage: prefs?.overrideLanguage,
          voiceIdentifier: prefs?.voiceIdentifier,
      ),
      engineFactory: {
        engine = AVTTSEngine()
        return engine!
      }
    )
    _ = self.synthesizer?.availableVoices // Hack to preload the engine, until we support rates and pitch in the toolkit
    engine?.delegate = self
    self.ttsPrefs = prefs
    self.synthesizer?.delegate = self
  }
  
  func ttsEnable(withPreferences ttsPrefs: TTSPreferences) async throws {
    print(TAG, "ttsEnable")
    try await setupSynthesizer(withPreferences: ttsPrefs)
  }

  func ttsStart(fromLocator: Locator?) {
    print(TAG, "ttsStart: fromLocator=\(fromLocator?.jsonString ?? "nil")")
    self.synthesizer?.start(from: fromLocator)
    setupNowPlaying()
  }

  func ttsStop() {
    self.synthesizer?.stop()
  }

  func ttsPause() {
    self.synthesizer?.pause()
  }

  func ttsResume() {
    self.synthesizer?.resume()
  }

  func ttsPauseOrResume() {
    self.synthesizer?.pauseOrResume()
  }

  func ttsNext() {
    self.synthesizer?.next()
  }

  func ttsPrevious() {
    self.synthesizer?.previous()
  }

  func ttsGetAvailableVoices() -> [TTSVoice] {
    return self.synthesizer?.availableVoices ?? []
  }
  
  func ttsSetVoice(voiceIdentifier: String) throws {
    print(TAG, "ttsSetVoice: voiceIdent=\(String(describing: voiceIdentifier))")

    /// Check that voice with given identifier exists
    guard let _ = synthesizer?.voiceWithIdentifier(voiceIdentifier) else {
      throw LibraryError.voiceNotFound
    }

    /// Changes will be applied for the next utterance.
    synthesizer?.config.voiceIdentifier = voiceIdentifier
  }
  
  func ttsSetPreferences(prefs: TTSPreferences) {
    self.ttsPrefs?.rate = prefs.rate ?? self.ttsPrefs?.rate
    self.ttsPrefs?.pitch = prefs.pitch ?? self.ttsPrefs?.pitch
    self.ttsPrefs?.voiceIdentifier = prefs.voiceIdentifier ?? self.ttsPrefs?.voiceIdentifier
    self.ttsPrefs?.overrideLanguage = prefs.overrideLanguage ?? self.ttsPrefs?.overrideLanguage
    self.synthesizer?.config.voiceIdentifier = prefs.voiceIdentifier
    self.synthesizer?.config.defaultLanguage = prefs.overrideLanguage
  }
  
  // MARK: - Protocol impl
  
  /// AVTTSEngineDelegate callback on creating new utterance
  public func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
    /// Rate must be normalized on iOS, since AVSpeechUtterance has a default rate of 0.5
    let avRate = min(max(Float(self.ttsPrefs?.rate ?? 1.0) * AVSpeechUtteranceDefaultSpeechRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    utterance.pitchMultiplier = Float(self.ttsPrefs?.pitch ?? 1.0)
    utterance.rate = avRate
  }

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    print(TAG, "publicationSpeechSynthesizerStateDidChange")
    var playingUtteranceLocator: Locator? = nil
    var playingRangeLocator: Locator? = nil

    switch state {
    case .playing(let utt, let range):
      /// utterance is a full sentence/paragraph, while range is the currently spoken part.
      playingUtteranceLocator = utt.locator
      playingRangeLocator = range
      if let newLocator = playingRangeLocator {
        // TODO: this should likely be throttled somewhat
        // See https://github.com/readium/swift-toolkit/blob/master/docs/Guides/TTS.md#turning-pages-automatically
        Task.detached(priority: .high) {
          await currentReaderView?.justGoToLocator(newLocator, animated: true)
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
       let uttDecorationStyle = ttsUtteranceDecorationStyle {
        decorations.append(Decoration(
          id: "tts-utterance", locator: locator, style: uttDecorationStyle
        ))
    }
    if let locator = playingRangeLocator,
       let rangeDecorationStyle = ttsRangeDecorationStyle {
      decorations.append(Decoration(
        id: "tts-range", locator: locator, style: rangeDecorationStyle
      ))
    }
    currentReaderView?.applyDecorations(decorations, forGroup: "tts")
  }

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    print(TAG, "publicationSpeechSynthesizerUtteranceDidFail: \(error)")
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
