import Combine
import MediaPlayer
import ReadiumShared
import ReadiumNavigator

public class FlutterAudioNavigator: FlutterTimeBasedNavigator, AudioNavigatorDelegate
{
  private let TAG = "FlutterAudioNavigator"
  private var _publication: Publication
  private var _initialLocator: Locator?
  private var _preferences: FlutterAudioPreferences
  private var _audioNavigator: AudioNavigator?
  
  internal var subscriptions: Set<AnyCancellable> = []
  internal var nowPlayingUpdater: NowPlayingInfoUpdater
  
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
    self.nowPlayingUpdater = NowPlayingInfoUpdater(withPublication: publication)
  }

  public func initNavigator() -> Void {
    _audioNavigator = AudioNavigator(
      publication: publication,
      initialLocation: initialLocator,
      config: AudioNavigator.Configuration(
        preferences: AudioPreferences(fromFlutterPrefs: _preferences)
      )
    )
    _audioNavigator?.delegate = self
    
    Task {
      cover = try? await publication.cover().get()
    }
  }
  
  public func setupNavigatorListeners() {
    /// Subscribe to changes
    $playback
      .throttle(for: 1, scheduler: RunLoop.main, latest: true)
      .sink { [weak self, TAG] info in
        guard let self = self else {
          return
        }
        debugPrint(TAG, "$playback updated.state=\(info.state),index=\(info.resourceIndex),time=\(info.time),progress=\(info.progress)")
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    _audioNavigator?.pause()
    _audioNavigator?.delegate = nil
    _audioNavigator = nil
  }

  public func play() async -> Void {
    _audioNavigator?.play()
    nowPlayingUpdater.setupNowPlayingInfo()
    setupCommandCenterControls()
  }

  public func play(fromLocator: Locator) async -> Void {
    // TODO: This
    //await _audioNavigator?.seek(to: )
    await play()
  }

  public func pause() async -> Void {
    _audioNavigator?.pause()
  }

  public func resume() async -> Void {
    _audioNavigator?.play()
  }

  public func seek(toLocator: Locator) async -> Void {
    // Seek to the specified locator
  }
  
  // MARK: AudioNavigatorDelegate
  
  /// Called when the playback updates.
  public func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    //
  }
  
  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    //
  }

  /// Called when the ranges of buffered media data change.
  /// Warning: They may be discontinuous.
  public func navigator(_ navigator: AudioNavigator, loadedTimeRangesDidChange ranges: [Range<Double>]) {
    //
  }
  
  /// Called when the navigator finished playing the current resource.
  /// Returns whether the next resource should be played. Default is true.
  public func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    return true
  }
  
  public func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
    //
  }
  
  public func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    //
  }
  
  // MARK: Control Center

  private func setupCommandCenterControls() {
    NowPlayingInfo.shared.media = .init(
      title: publication.metadata.title ?? "",
      artist: publication.metadata.authors.map(\.name).joined(separator: ", "),
      artwork: cover
    )

    let rcc = MPRemoteCommandCenter.shared()

    func on(_ command: MPRemoteCommand, _ block: @escaping (AudioNavigator, MPRemoteCommandEvent) -> Void) {
      command.addTarget { [weak self] event in
        guard let self = self,
              let navigator = self._audioNavigator else {
          return .noActionableNowPlayingItem
        }
        block(navigator, event)
        return .success
      }
    }

    on(rcc.playCommand) { audioNavigator, _ in
      audioNavigator.play()
    }

    on(rcc.pauseCommand) { audioNavigator, _ in
      audioNavigator.pause()
    }

    on(rcc.togglePlayPauseCommand) { audioNavigator, _ in
      audioNavigator.playPause()
    }

    on(rcc.previousTrackCommand) { audioNavigator, _ in
      Task {
        await audioNavigator.goBackward()
      }
    }

    on(rcc.nextTrackCommand) { audioNavigator, _ in
      Task {
        await audioNavigator.goForward()
      }
    }

    let seekInterval = self._preferences.seekInterval ?? 30

    rcc.skipBackwardCommand.preferredIntervals = [seekInterval as NSNumber]
    on(rcc.skipBackwardCommand) { [seekInterval] audioNavigator, _ in
      Task {
        await audioNavigator.seek(by: -(seekInterval))
      }
    }

    rcc.skipForwardCommand.preferredIntervals = [seekInterval as NSNumber]
    on(rcc.skipForwardCommand) { [seekInterval] audioNavigator, _ in
      Task {
        await audioNavigator.seek(by: +(seekInterval))
      }
    }

    on(rcc.changePlaybackPositionCommand) { audioNavigator, event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return
      }
      Task {
        await audioNavigator.seek(to: event.positionTime)
      }
    }
  }

  private func updateCommandCenterControls() {
    let rcc = MPRemoteCommandCenter.shared()
    rcc.previousTrackCommand.isEnabled = _audioNavigator?.canGoBackward ?? false
    rcc.nextTrackCommand.isEnabled = _audioNavigator?.canGoForward ?? false
  }
}
