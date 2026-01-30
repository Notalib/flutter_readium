import Combine
import AVFAudio
import ReadiumShared
import ReadiumNavigator

public class FlutterTTSNavigator: FlutterTimebasedNavigator, PublicationSpeechSynthesizerDelegate, AVTTSEngineDelegate
{
  private let TAG = "FlutterTTSNavigator"
  private var _publication: Publication
  private var _initialLocator: Locator?

  internal var synthesizer: PublicationSpeechSynthesizer?
  internal var engine: AVTTSEngine?
  internal var preferences: TTSPreferences
  internal var nowPlayingUpdater: NowPlayingInfoUpdater

  /// TTS related variables
  @Published internal var playingUtterance: Locator?
  internal let playingWordRangeSubject = PassthroughSubject<Locator, Never>()
  internal var subscriptions: Set<AnyCancellable> = []
  internal var isMoving = false

  public var publication: Publication {
    get {
      return self._publication
    }
  }
  public var initialLocator: Locator? {
    get {
      return self._initialLocator
    }
  }

  public var listener: (any TimebasedListener)?

  public init(
    publication: Publication,
    preferences: TTSPreferences = TTSPreferences.init(),
    initialLocator: Locator?
  ) {
    self._publication = publication
    self._initialLocator = initialLocator
    self.preferences = preferences
    self.nowPlayingUpdater = .init(withPublication: publication)
  }

  public func initNavigator() -> Void {
    self.engine = AVTTSEngine()
    self.synthesizer = PublicationSpeechSynthesizer(
      publication: publication,
      config: PublicationSpeechSynthesizer.Configuration(
        defaultLanguage: preferences.overrideLanguage,
        voiceIdentifier: preferences.voiceIdentifier,
      ),
      engineFactory: {
        return self.engine!
      }
    )!
    engine?.delegate = self
    self.synthesizer?.delegate = self

    // TODO: Why is this public, if always called from itself?
    self.setupNavigatorListeners()
  }

  public func setupNavigatorListeners() -> Void {
    $playingUtterance
      .removeDuplicates()
      .sink { [weak self] locator in
        guard let self = self, let locator = locator else {
          return
        }
        debugPrint(TAG, "tts send audio-locator")
        let chapterNo = publication.readingOrder.firstIndexWithHREF(locator.href)
        let link = self.publication.readingOrder.firstWithHREF(locator.href)

        self.nowPlayingUpdater.updateChapterNo(chapterNo)
        self.nowPlayingUpdater.updateCommandCenterControls()
        listener?.timebasedNavigator(self, reachedLocator: locator, readingOrderLink: link)
      }
      .store(in: &subscriptions)

    playingWordRangeSubject
      .removeDuplicates()
    // Improve performances by throttling the reader sync
      .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
      .sink { [weak self] locator in
        guard let self = self else {
          return
        }

        debugPrint(TAG, "sync reader to locator")
        let link = self.publication.readingOrder.firstWithHREF(locator.href)
        listener?.timebasedNavigator(self, reachedLocator: locator, readingOrderLink: link)
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    nowPlayingUpdater.clearNowPlaying()
    self.subscriptions.forEach { $0.cancel() }
    self.synthesizer?.stop()
    self.synthesizer?.delegate = nil
    self.engine?.delegate = nil
    self.listener?.timebasedNavigator(self, didChangeState: .init(state: .ended))
    self.listener = nil
  }

  public func play(fromLocator: Locator?) async -> Void {
    self.synthesizer?.start(from: fromLocator)
    nowPlayingUpdater.setupNowPlayingInfo()
    nowPlayingUpdater.setupCommandCenterControls(
      preferredIntervals: [],
      skipTrackEnabled: true,
      timebasedNavigator: self
    )
  }

  public func pause() async -> Void {
    self.synthesizer?.pause()
  }

  public func resume() async -> Void {
    self.synthesizer?.resume()
  }

  public func togglePlayPause() async -> Void {
    guard let synth = self.synthesizer else {
      return
    }
    if case .playing(_,_) = synth.state {
      await self.pause()
    } else {
      await self.play(fromLocator: nil)
    }
  }

  public func seekForward() async -> Bool {
    self.synthesizer?.next()
    return true
  }

  public func seekBackward() async -> Bool {
    self.synthesizer?.previous()
    return true
  }

  public func seek(toLocator: Locator) async -> Bool {
    self.synthesizer?.start(from: toLocator)
    return true
  }

  public func seekRelative(byOffsetSeconds: Double) async -> Bool {
    // Cannot be implemented for TTS
    return false
  }

  public func seek(toOffset: Double) async -> Bool {
    // Cannot be implemented for TTS
    return false
  }

  // MARK: TTS Specific APIs

  func ttsSetPreferences(prefs: TTSPreferences) {
    preferences.rate = prefs.rate
    preferences.pitch = prefs.pitch
    preferences.voiceIdentifier = prefs.voiceIdentifier
    preferences.overrideLanguage = prefs.overrideLanguage
    self.synthesizer?.config.voiceIdentifier = preferences.voiceIdentifier
    self.synthesizer?.config.defaultLanguage = preferences.overrideLanguage
  }

  func ttsGetAvailableVoices() -> [TTSVoice] {
    return self.synthesizer?.availableVoices ?? []
  }

  func ttsSetVoice(voiceIdentifier: String) throws {
    debugPrint(TAG, "ttsSetVoice: voiceIdent=\(String(describing: voiceIdentifier))")

    /// Check that voice with given identifier exists
    guard let _ = synthesizer?.voiceWithIdentifier(voiceIdentifier) else {
      throw ReadiumError.voiceNotFound
    }

    /// Changes will be applied for the next utterance.
    synthesizer?.config.voiceIdentifier = voiceIdentifier
  }

  // MARK: PublicationSpeechSynthesizerDelegate

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    debugPrint(TAG, "publicationSpeechSynthesizerStateDidChange")

    switch state {
    case let .playing(utt, wordRange):
      debugPrint(TAG, "tts playing")
      /// utterance is a full sentence/paragraph, while range is the currently spoken part.
      playingUtterance = utt.locator
      if let wordRange = wordRange {
        playingWordRangeSubject.send(wordRange)
      }
      self.listener?.timebasedNavigator(self, requestsHighlightAt: utt.locator, withWordLocator: wordRange)
    case let .paused(utt):
      debugPrint(TAG, "tts paused at utterance: \(utt.text)")
      playingUtterance = utt.locator
    case .stopped:
      playingUtterance = nil
      debugPrint(TAG, "tts stopped")
      self.listener?.timebasedNavigator(self, requestsHighlightAt: nil, withWordLocator: nil)
      //updateDecorations(uttLocator: nil, rangeLocator: nil)
      self.nowPlayingUpdater.clearNowPlaying()
    }

    let state = ReadiumTimebasedState(state: state.asTimebasedState, currentLocator: playingUtterance)
    self.listener?.timebasedNavigator(self, didChangeState: state)
  }

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    debugPrint(TAG, "publicationSpeechSynthesizerUtteranceDidFail: \(error)")

    self.listener?.timebasedNavigator(self, encounteredError: error, withDescription: "TTSUtteranceFailed")

    //TODO: How can both Reader and Plugin submit on this channel?
    //let error = FlutterReadiumError(message: error.localizedDescription, code: "TTSUtteranceFailed", data: utterance.text)
    //self.errorStreamHandler?.sendEvent(error)
  }

  // MARK: AVTTSEngineDelegate

  public func avTTSEngine(_ engine: ReadiumNavigator.AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
    // This is the place to hook into, in order to change rate & pitch for TTS.
    utterance.rate = preferences.rate ?? AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = preferences.pitch ?? 1.0
  }
}
