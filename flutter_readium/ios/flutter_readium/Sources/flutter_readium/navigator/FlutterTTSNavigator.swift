import Combine
import AVFAudio
import ReadiumShared
import ReadiumNavigator

public class FlutterTTSNavigator: FlutterTimebasedNavigator, PublicationSpeechSynthesizerDelegate, AVTTSEngineDelegate
{
  private var _publication: Publication
  private var _initialLocator: Locator?

  internal var synthesizer: PublicationSpeechSynthesizer?
  internal var engine: AVTTSEngine?
  internal var preferences: TTSPreferences
  internal var nowPlayingUpdater: NowPlayingInfoUpdater

  /// TTS related variables
  @Published internal var playingUtterance: Locator?
  @Published internal var playingWordRange: Locator?
  internal var subscriptions: Set<AnyCancellable> = []
  internal var progressionLookup: [AnyURL: [Locator]] = [:]

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
  public var currentLocator: Locator? {
    get {
      return playingUtterance
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
    self.nowPlayingUpdater = .init(
      withPublication: publication,
      infoType: preferences.controlPanelInfoType ?? .standard,
      timebase: preferences.controlPanelTimebase ?? .chapter
    )
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

    self.setupNavigatorStateListeners()
  }

  private func setupNavigatorStateListeners() -> Void {
    $playingUtterance
      .removeDuplicates()
      .sink { [weak self] locator in
        guard let self = self, let locator = locator else {
          return
        }
        Log.navigator.debug("TTS utterance changed")
        let chapterNo = publication.readingOrder.firstIndexWithHREF(locator.href)

        self.nowPlayingUpdater.updateChapterNo(chapterNo)
        self.nowPlayingUpdater.updateCommandCenterControls()
        listener?.timebasedNavigator(self, reachedLocator: locator, segmentDuration: nil, isWordRange: false)
      }
      .store(in: &subscriptions)

    $playingWordRange
      .removeDuplicates()
    // Improve performance by throttling the reader sync
      .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
      .sink { [weak self] locator in
        guard let self = self, let locator = locator else {
          return
        }

        // Word-range syncs are flagged so the reader view can ignore them in
        // scroll mode (where they cause snap-to-top jitter) while still
        // following them in pagination — there an utterance spanning a page
        // boundary should turn the page to the word currently being spoken.
        Log.navigator.debug("Sync reader-view to new TTS locator")
        listener?.timebasedNavigator(self, reachedLocator: locator, segmentDuration: nil, isWordRange: true)
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    self.subscriptions.forEach { $0.cancel() }
    if (self.synthesizer != nil) {
      self.synthesizer?.stop()
      self.synthesizer?.delegate = nil
      self.engine?.delegate = nil
      self.listener?.timebasedNavigator(self, didChangeState: .init(state: .none))
    }
    self.listener = nil
    nowPlayingUpdater.clearNowPlaying()
  }

  public func play(fromLocator: Locator?) async -> Void {
    self.synthesizer?.start(from: fromLocator ?? initialLocator)
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

  public func seek(toProgression: Double) async -> Bool {
    guard let currentHref = (currentLocator ?? initialLocator)?.href else {
      return false
    }
    let link = publication.readingOrder.firstWithHREF(currentHref)
    let baseLocator = Locator(href: currentHref, mediaType: link?.mediaType ?? .xhtml)
      .copyWithProgressionLocations(progression: toProgression)
    let resolvedLocator = await resolveLocatorWithProgression(baseLocator) ?? baseLocator
    return await seek(toLocator: resolvedLocator)
  }

  public func seekRelative(byOffsetSeconds: Double) async -> Bool {
    // Cannot be implemented for TTS
    return false
  }

  public func seek(toOffset: Double) async -> Bool {
    // Cannot be implemented for TTS
    return false
  }

  public func decorationsUpdated() -> Void {
    if let currentUtterance = playingUtterance {
      let currentWordRange = playingWordRange
      self.listener?.timebasedNavigator(self, requestsHighlightAt: currentUtterance, withWordLocator: currentWordRange)
    } else {
      Log.navigator.warn("Could not update decorations, no current Locator")
    }
  }

  // MARK: TTS Specific APIs

  func ttsSetPreferences(prefs: TTSPreferences) {
    preferences.rate = prefs.rate
    preferences.pitch = prefs.pitch
    preferences.voiceIdentifier = prefs.voiceIdentifier
    preferences.overrideLanguage = prefs.overrideLanguage
    preferences.controlPanelInfoType = prefs.controlPanelInfoType
    preferences.controlPanelTimebase = prefs.controlPanelTimebase
    nowPlayingUpdater.infoType = prefs.controlPanelInfoType ?? .standard
    nowPlayingUpdater.timebase = prefs.controlPanelTimebase ?? .chapter
    self.synthesizer?.config.voiceIdentifier = preferences.voiceIdentifier
    self.synthesizer?.config.defaultLanguage = preferences.overrideLanguage
  }

  func ttsGetAvailableVoices() -> [TTSVoice] {
    return self.synthesizer?.availableVoices ?? []
  }

  func ttsSetVoice(voiceIdentifier: String) throws {
    Log.navigator.info("ttsSetVoice: voiceIdent=\(String(describing: voiceIdentifier))")

    /// Check that voice with given identifier exists
    guard let _ = synthesizer?.voiceWithIdentifier(voiceIdentifier) else {
      throw ReadiumError.voiceNotFound
    }

    /// Changes will be applied for the next utterance.
    synthesizer?.config.voiceIdentifier = voiceIdentifier
  }

  // MARK: PublicationSpeechSynthesizerDelegate

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, stateDidChange state: ReadiumNavigator.PublicationSpeechSynthesizer.State) {
    Log.navigator.debug("publicationSpeechSynthesizerStateDidChange")

    switch state {
    case let .playing(utt, wordRange):
      Log.navigator.info("TTS state: playing")
      let enrichedLocator = utteranceLocatorWithPosition(utt.locator)
      playingUtterance = enrichedLocator
      if let wordRange = wordRange {
        playingWordRange = wordRange
      }
      self.listener?.timebasedNavigator(self, requestsHighlightAt: enrichedLocator, withWordLocator: wordRange)
    case let .paused(utt):
      Log.navigator.info("TTS paused at utterance: \(utt.text)")
      playingUtterance = utteranceLocatorWithPosition(utt.locator)
    case .stopped:
      playingUtterance = nil
      Log.navigator.info("TTS state: stopped")
      self.listener?.timebasedNavigator(self, requestsHighlightAt: nil, withWordLocator: nil)
      //updateDecorations(uttLocator: nil, rangeLocator: nil)
      self.nowPlayingUpdater.clearNowPlaying()
    }

    let state = ReadiumTimebasedState(state: state.asTimebasedState, currentLocator: playingUtterance)
    self.listener?.timebasedNavigator(self, didChangeState: state)
  }

  public func publicationSpeechSynthesizer(_ synthesizer: ReadiumNavigator.PublicationSpeechSynthesizer, utterance: ReadiumNavigator.PublicationSpeechSynthesizer.Utterance, didFailWithError error: ReadiumNavigator.PublicationSpeechSynthesizer.Error) {
    Log.navigator.error("SpeechSynthesizer failed with error: \(error)")

    // Emits the specific TTSUtteranceFailed code directly rather than routing through
    // the generic timebasedNavigator(encounteredError:) sink, which would additionally
    // emit a duplicate, misclassified ResourceReadError event for the same failure.
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(FlutterReadiumError(message: error.localizedDescription, code: "TTSUtteranceFailed", data: ["message": utterance.text]).toJsonString())
  }

  // MARK: AVTTSEngineDelegate

  public func avTTSEngine(_ engine: ReadiumNavigator.AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
    // This is the place to hook into, in order to change rate & pitch for TTS.
    utterance.rate = preferences.rate ?? AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = preferences.pitch ?? 1.0
  }

  // MARK: From progression

  private func resolveLocatorWithProgression(_ locator: Locator) async -> Locator? {
    guard locator.locations.cssSelector == nil,
          let progression = locator.locations.progression else {
      return locator
    }
    return await findLocatorFromProgression(progression, inHref: locator.href) ?? locator
  }

  // Builds the utterance locator with a reading-order position attached in one step,
  // so the @Published subscriber fires exactly once per utterance — not once per word.
  // Doing two separate assignments (raw locator, then mutate position) defeats
  // removeDuplicates(): every word-range state change would reset position to nil and
  // re-trigger the subscriber, snapping the view back to the utterance's start page.
  private func utteranceLocatorWithPosition(_ locator: Locator) -> Locator {
    guard let idx = publication.readingOrder.firstIndexWithHREF(locator.href) else {
      return locator
    }
    var enriched = locator
    enriched.locations.position = idx + 1
    return enriched
  }

  private func findLocatorFromProgression(_ progression: Double, inHref href: AnyURL) async -> Locator? {
    guard let items = await getProgressionLocators(forHref: href) else {
      return nil
    }

    if progression == 1.0 {
      return items.last
    }

    /// Find the Locator inside this resource with nearest progression.
    var lastItem: Locator? = nil
    for item in items {
      if item.locations.progression == progression { return item }
      if let itemProgression = item.locations.progression, itemProgression > progression {
        return lastItem ?? item
      }
      lastItem = item
    }

    return nil
  }

  private func getProgressionLocators(forHref href: AnyURL) async -> [Locator]? {
    if let cached = progressionLookup[href] {
      return cached
    }

    let mediaType = publication.readingOrder.firstWithHREF(href)?.mediaType ?? .xhtml
    let startLocator = Locator(href: href, mediaType: mediaType)

    guard let content = publication.content(from: startLocator) else {
      Log.navigator.error("updateProgressionLocatorMap - no content service found")
      return nil
    }

    var items: [Locator] = []
    let iterator = content.iterator()
    while let element = try? await iterator.next() {
      guard let textElement = element as? TextContentElement else { continue }
      let elementLocator = textElement.locator
      guard elementLocator.locations.progression != nil else { continue }
      guard elementLocator.href.isEquivalentTo(href) else { break }
      items.append(elementLocator)
    }

    progressionLookup[href] = items
    return items
  }
}
