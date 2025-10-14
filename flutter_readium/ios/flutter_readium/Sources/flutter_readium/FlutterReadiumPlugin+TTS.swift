import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin/TTS"

extension FlutterReadiumPlugin : PublicationSpeechSynthesizerDelegate, AVTTSEngineDelegate {

  fileprivate func setupSynthesizer(withPreferences prefs: TTSPreferences?) async throws {
    print(TAG, "setupSynthesizer")

    var engine: AVTTSEngine?

    guard let publication = getCurrentPublication() else {
      throw ReadiumError.notFound("No current publication")
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
    engine?.delegate = self
    self.ttsPrefs = prefs
    self.synthesizer?.delegate = self

    $playingUtterance
      .removeDuplicates()
      .sink { [weak self] locator in
        guard let self = self else {
          return
        }
        print(TAG, "tts send audio-locator")
        audioLocatorStreamHandler?.sendEvent(locator)
      }
      .store(in: &subscriptions)

    playingWordRangeSubject
      .removeDuplicates()
      //  Improve performances by throttling the moves to maximum one per second.
      .throttle(for: 1, scheduler: RunLoop.main, latest: true)
      .drop(while: { [weak self] _ in self?.isMoving ?? true })
      .sink { [weak self] locator in
        guard let self = self else {
          return
        }

        print(TAG, "tts navigate reader to locator")
        isMoving = true
        Task {
          let _ = await self.syncWithAudioLocator(locator)
          self.isMoving = false
        }
      }
      .store(in: &subscriptions)
  }

  @MainActor
  func updateDecorations(uttLocator: Locator?, rangeLocator: Locator?) {
    // Update Reader text decorations
    var decorations: [Decoration] = []
    if let uttLocator = uttLocator,
       let uttDecorationStyle = ttsUtteranceDecorationStyle {
        decorations.append(Decoration(
          id: "tts-utterance", locator: uttLocator, style: uttDecorationStyle
        ))
    }
    if let rangeLocator = rangeLocator,
       let rangeDecorationStyle = ttsRangeDecorationStyle {
      decorations.append(Decoration(
        id: "tts-range", locator: rangeLocator, style: rangeDecorationStyle
      ))
    }
    currentReaderView?.applyDecorations(decorations, forGroup: "tts")
  }

  func ttsEnable(withPreferences ttsPrefs: TTSPreferences) async throws {
    print(TAG, "ttsEnable")
    try await setupSynthesizer(withPreferences: ttsPrefs)
  }

  func ttsStart(fromLocator: Locator?) {
    print(TAG, "ttsStart: fromLocator=\(fromLocator?.jsonString ?? "nil")")
    self.synthesizer?.start(from: fromLocator)
    setupTTSNowPlaying()
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
      throw ReadiumError.voiceNotFound
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

  // MARK: - Protocol impl.

  public func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
    utterance.rate = self.ttsPrefs?.rate ?? AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = self.ttsPrefs?.pitch ?? 1.0
  }


  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    print(TAG, "publicationSpeechSynthesizerStateDidChange")

    switch state {
    case let .playing(utt, wordRange):
      print(TAG, "tts playing")
      /// utterance is a full sentence/paragraph, while range is the currently spoken part.
      playingUtterance = utt.locator
      if let wordRange = wordRange {
        playingWordRangeSubject.send(wordRange)
      }
      updateDecorations(uttLocator: utt.locator, rangeLocator: wordRange)
    case let .paused(utt):
      print(TAG, "tts paused at utterance: \(utt.text)")
      playingUtterance = utt.locator
    case .stopped:
      playingUtterance = nil
      print(TAG, "tts stopped")
      updateDecorations(uttLocator: nil, rangeLocator: nil)
      clearNowPlaying()
    }
  }

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    print(TAG, "publicationSpeechSynthesizerUtteranceDidFail: \(error)")

    //TODO: How can both Reader and Plugin submit on this channel?
    //let error = FlutterReadiumError(message: error.localizedDescription, code: "TTSUtteranceFailed", data: utterance.text)
    //self.errorStreamHandler?.sendEvent(error)
  }

  // MARK: - Now Playing

  // This will display the publication in the Control Center and support
  // external controls.

  private func setupTTSNowPlaying() {
    Task {
      guard let publication = getCurrentPublication() else {
        throw ReadiumError.notFound("No current publication")
      }
      NowPlayingInfo.shared.media = .init(
        title: publication.metadata.title ?? "",
        artist: publication.metadata.authors.map(\.name).joined(separator: ", "),
      )

      // Async load the cover.
      let cover = try? await publication.cover().get()
      NowPlayingInfo.shared.media?.artwork = cover
    }

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.ttsPauseOrResume()
      return .success
    }
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.ttsNext()
      return .success
    }
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.ttsPrevious()
      return .success
    }
  }
}
