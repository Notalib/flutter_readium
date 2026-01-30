import Combine
import MediaPlayer
import ReadiumShared
import ReadiumNavigator

public class FlutterAudioNavigator: FlutterTimebasedNavigator, AudioNavigatorDelegate
{
  internal let TAG = "FlutterAudioNavigator"

  internal var _publication: Publication
  internal var _initialLocator: Locator?
  internal var _preferences: FlutterAudioPreferences
  internal var _lastTimebasedPlayerState: ReadiumTimebasedState?
  internal var _nowPlayingUpdater: NowPlayingInfoUpdater
  @MainActor internal var _audioNavigator: AudioNavigator?

  internal var subscriptions: Set<AnyCancellable> = []

  @Published var cover: UIImage?
  @Published var playback: MediaPlaybackInfo = .init()

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

  public init(publication: Publication, preferences: FlutterAudioPreferences, initialLocator: Locator?) {
    self._publication = publication
    self._preferences = preferences
    self._initialLocator = initialLocator
    self._nowPlayingUpdater = NowPlayingInfoUpdater(
      withPublication: publication,
      infoType: preferences.controlPanelInfoType
    )
  }

  public func initNavigator() async -> Void {
    _audioNavigator = AudioNavigator(
      publication: publication,
      initialLocation: initialLocator,
      config: AudioNavigator.Configuration(
        preferences: AudioPreferences(fromFlutterPrefs: _preferences)
      )
    )
    _audioNavigator?.delegate = self

    // TODO: Why is this public, if always called from itself?
    self.setupNavigatorListeners()

    Task {
      cover = try? await publication.cover().get()
    }
  }

  public func setupNavigatorListeners() {
    /// Subscribe to changes
    $playback
      .throttle(for: .seconds(self._preferences.updateIntervalSecs), scheduler: RunLoop.main, latest: true)
      .sink { [weak self, TAG] info in
        guard let self = self else {
          return
        }
        debugPrint(TAG, "$playback updated: state=\(info.state),index=\(info.resourceIndex),time=\(info.time),progress=\(info.progress)")

        if let location = _audioNavigator?.currentLocation {
          self.submitTimebasedPlayerStateToListener(info: info, location: location)
        }
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    self._audioNavigator?.pause()
    self._audioNavigator?.delegate = nil
    self._audioNavigator = nil
    self.listener?.timebasedNavigator(self, didChangeState: .init(state: .ended))
    self.listener = nil
  }

  public func play(fromLocator: Locator?) async -> Void {
    if (fromLocator != nil) {
      let _ = await seek(toLocator: fromLocator!)
    }
    _audioNavigator?.play()
    _nowPlayingUpdater.setupNowPlayingInfo()
    _nowPlayingUpdater.setupCommandCenterControls(
      preferredIntervals: [_preferences.seekInterval],
      seekToEnabled: _preferences.allowExternalSeeking,
      timebasedNavigator: self
    )
  }

  public func pause() async -> Void {
    _audioNavigator?.pause()
  }

  public func resume() async -> Void {
    _audioNavigator?.play()
  }

  public func togglePlayPause() async -> Void {
    if (playback.state == .playing) {
      await pause()
    } else {
      await resume()
    }
  }

  public func seekForward() async -> Bool {
    await _audioNavigator?.seek(by: self._preferences.seekInterval)
    return true
  }

  public func seekBackward() async -> Bool {
    await _audioNavigator?.seek(by: -1 * self._preferences.seekInterval)
    return true
  }

  public func seek(toLocator: Locator) async -> Bool {
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    let navigated = await _audioNavigator?.go(to: toLocator) ?? false
    if (wasPlaying && navigated) {
      _audioNavigator?.play()
    }
    return navigated
  }

  public func seek(toOffset: Double) async -> Bool {
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    await _audioNavigator?.seek(to: toOffset)
    if (wasPlaying) {
      _audioNavigator?.play()
    }
    return true
  }
  
  public func seekRelative(byOffsetSeconds: Double) async -> Bool {
    await _audioNavigator?.seek(by: byOffsetSeconds)
    return true
  }

  // MARK: AudioNavigatorDelegate

  /// Called when the playback updates.
  public func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    self._nowPlayingUpdater.updatePlaybackFromInfo(info, withSpeedSetting: _audioNavigator?.settings.speed)
    self._nowPlayingUpdater.updateCommandCenterControls()
    self.playback = info
  }

  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    // Submit new locator to the listener
    self.submitAudioLocatorToListener(locator)

    if let info = _audioNavigator?.playbackInfo {
      self.submitTimebasedPlayerStateToListener(info: info, location: locator)
    }
  }

  /// Called when the ranges of buffered media data change.
  /// Warning: They may be discontinuous.
  public func navigator(_ navigator: AudioNavigator, loadedTimeRangesDidChange ranges: [Range<Double>]) {
    // Simplified buffer range to TimeInterval, by just taking highest upper bound.
    // May be too optimistic if ranges are discontinuous.
    let highestUpperBound: TimeInterval = ranges.map(\.upperBound).max() ?? 0

    if let info = _audioNavigator?.playbackInfo,
       let location = _audioNavigator?.currentLocation {
      self.submitTimebasedPlayerStateToListener(info: info, location: location, bufferedInterval: highestUpperBound)
    }
  }

  /// Called when the navigator finished playing the current resource.
  /// Returns whether the next resource should be played. Default is true.
  public func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    return true
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
    debugPrint(TAG, "presentError: \(error)")
    // TODO: Only relevant when supporting LCP, error can only be copyForbidden.
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    self.listener?.timebasedNavigator(self, encounteredError: error, withDescription: "DidFailToLoadResourceAt: \(href)")
  }

  // MARK: AudioNavigator specific API

  @MainActor
  func setAudioPreferences(_ preferences: FlutterAudioPreferences) {
    self._preferences = preferences
    /// Update the Audio Navigator.
    self._audioNavigator?.submitPreferences(AudioPreferences(fromFlutterPrefs: preferences))
    /// Update the CommandCenter controls.
    self._nowPlayingUpdater.setupCommandCenterControls(
      preferredIntervals: [_preferences.seekInterval],
      seekToEnabled: _preferences.allowExternalSeeking,
      timebasedNavigator: self
    )
  }

  var canGoBackward: Bool {
    self._audioNavigator?.canGoBackward ?? false
  }

  var canGoForward: Bool {
    self._audioNavigator?.canGoForward ?? false
  }

  @MainActor
  public func skipForward() async -> Bool {
    if _audioNavigator?.canGoForward != true {
      return false
    }
    return await _audioNavigator?.goForward() ?? false
  }

  @MainActor
  public func skipBackward() async -> Bool {
    if _audioNavigator?.canGoBackward != true {
      return false
    }
    return await _audioNavigator?.goBackward() ?? false
  }

  // MARK: Internal AudioNavigator API

  internal func submitAudioLocatorToListener(_ locator: Locator) {
    let readingOrderLink = self.publication.readingOrder.firstWithHREF(locator.href)
    self.listener?.timebasedNavigator(self, reachedLocator: locator, readingOrderLink: readingOrderLink)
  }

  internal func submitTimebasedPlayerStateToListener(info: MediaPlaybackInfo, location: Locator, bufferedInterval: TimeInterval? = nil) {
    // Create TimebasedState and send it over the timebased-state stream.
    let state = ReadiumTimebasedState(
      state: info.state.asTimebasedState,
      currentOffset: info.time,
      currentBuffered: bufferedInterval,
      currentDuration: info.duration ?? nil,
      currentLocator: location
    )

    // If state has changed, submit it to listener.
    if (state != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = state
      self.listener?.timebasedNavigator(self, didChangeState: state)
    } else {
      debugPrint(TAG, "Skipped state submission - duplicate")
    }
  }
}
