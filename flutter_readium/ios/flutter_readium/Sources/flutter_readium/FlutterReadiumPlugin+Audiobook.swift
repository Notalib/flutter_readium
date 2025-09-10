import Combine
import Foundation
import MediaPlayer
import ReadiumNavigator
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin/Audiobook"

//@MainActor
class AudiobookViewModel: ObservableObject {
  let navigator: AudioNavigator
  var preferences: FlutterAudioPreferences

  @Published var cover: UIImage?
  @Published var playback: MediaPlaybackInfo = .init()

  init(navigator: AudioNavigator, preferences: FlutterAudioPreferences) {
    self.navigator = navigator
    self.preferences = preferences

    Task {
      cover = try? await navigator.publication.cover().get()
    }
  }

  func onPlaybackChanged(info: MediaPlaybackInfo) {
    playback = info
  }
}

extension FlutterReadiumPlugin : AudioNavigatorDelegate {

  @MainActor func setupAudiobookNavigator(
      publication: Publication,
      initialLocator: Locator?,
      initialPreferences: FlutterAudioPreferences,
  ) async {
    let navigator = AudioNavigator(
      publication: publication,
      initialLocation: initialLocator,
      config: AudioNavigator.Configuration(
        preferences: AudioPreferences(fromFlutterPrefs: initialPreferences)
      )
    )
    if (audiobookVM != nil) {
      await endAudiobookNavigator()
    }

    audiobookVM = AudiobookViewModel(
      navigator: navigator,
      preferences: initialPreferences
    )
    navigator.delegate = self

    /// Subscribe to changes
    audiobookVM?.$playback
      .throttle(for: 1, scheduler: RunLoop.main, latest: true)
      .sink { [weak self] info in
        guard let self = self else {
          return
        }
        print(TAG, "model.$playback updated.state=\(info.state),index=\(info.resourceIndex),time=\(info.time),progress=\(info.progress)")
      }
      .store(in: &subscriptions)
  }
  
  public func setAudioPreferences(prefs: FlutterAudioPreferences) {
    self.audiobookVM?.preferences = prefs
    self.audiobookVM?.navigator.submitPreferences(AudioPreferences(fromFlutterPrefs: prefs))
  }

  public func endAudiobookNavigator() async {
    self.audiobookVM?.navigator.pause()
    self.audiobookVM = nil
    clearNowPlaying()
  }

  public func pause() {
    audiobookVM?.navigator.pause()
  }

  public func play() {
    Task {
      audiobookVM?.navigator.play()
      await setupNowPlaying()
      setupCommandCenterControls()
    }
  }

  public func playPause() {
    audiobookVM?.navigator.playPause()
  }

  public func goForward(animated: Bool) async -> Bool {
    let navOptions = animated ? NavigatorGoOptions.animated : NavigatorGoOptions.none
    if (audiobookVM?.navigator.canGoForward == true) {
      return await audiobookVM?.navigator.goForward(options: navOptions) == true
    } else {
      return false
    }
  }

  public func goBackward(animated: Bool) async -> Bool {
    let navOptions = animated ? NavigatorGoOptions.animated : NavigatorGoOptions.none
    if (audiobookVM?.navigator.canGoBackward == true) {
      return await audiobookVM?.navigator.goBackward(options: navOptions) == true
    } else {
      return false
    }
  }

  public func seek(by delta: Double) async {
    await audiobookVM?.navigator.seek(by: delta)
  }

  public func seek(to offset: Double) async {
    await audiobookVM?.navigator.seek(to: offset)
  }

  public func navigator(_ navigator: Navigator, locationDidChange location: Locator) {
    print(TAG, "locationDidChange: \(location.locations.progression ?? 0)")
  }

  // MARK: - AudioNavigatorDelegate (MainActor)

  /// Called when the playback updates.
  public func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    print(TAG, "playbackDidChange: \(info)")
    switch info.state {
    case .loading:
      print(TAG, "loading")
    case .playing:
      print(TAG, "playing")
    case .paused:
      print(TAG, "paused")
    }

    audiobookVM?.onPlaybackChanged(info: info)
    updateNowPlaying(info: info)
    updateCommandCenterControls()
  }

  /// Called when the navigator finished playing the current resource.
  /// Returns whether the next resource should be played. Default is true.
  public func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    print(TAG, "shouldPlayNextResource? (true)")
    return true
  }

  /// Called when the ranges of buffered media data change.
  /// Warning: They may be discontinuous.
  public func navigator(_ navigator: AudioNavigator, loadedTimeRangesDidChange ranges: [Range<Double>]) {
    print(TAG, "loadedTimeRangesDidChange: \(ranges)")
  }

  // MARK: - AudioNavigatorDelegate

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
    print(TAG, "presentError: \(error.localizedDescription)")
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    print(TAG, "didFailToLoadResourceAt: \(href.string), err: \(error.localizedDescription)")
  }

  private func setupCommandCenterControls() {
    Task {
      let publication = audiobookVM?.navigator.publication
        NowPlayingInfo.shared.media = await .init(
          title: publication?.metadata.title ?? "",
            artist: publication?.metadata.authors.map(\.name).joined(separator: ", "),
            artwork: try? publication?.cover().get()
        )
    }

    let rcc = MPRemoteCommandCenter.shared()

    func on(_ command: MPRemoteCommand, _ block: @escaping (AudioNavigator, MPRemoteCommandEvent) -> Void) {
        command.addTarget { [weak self] event in
            guard let self = self else {
                return .noActionableNowPlayingItem
            }
            block(self.audiobookVM!.navigator, event)
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

    rcc.skipBackwardCommand.preferredIntervals = [10]
    on(rcc.skipBackwardCommand) { audioNavigator, _ in
      Task {
        await audioNavigator.seek(by: -(self.audiobookVM?.preferences.seekInterval ?? 30))
      }
    }

    rcc.skipForwardCommand.preferredIntervals = [30]
    on(rcc.skipForwardCommand) { audioNavigator, _ in
      Task {
        await audioNavigator.seek(by: +(self.audiobookVM?.preferences.seekInterval ?? 30))
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
    rcc.previousTrackCommand.isEnabled = audiobookVM?.navigator.canGoBackward ?? false
    rcc.nextTrackCommand.isEnabled = audiobookVM?.navigator.canGoForward ?? false
  }

  // MARK: - Now Playing metadata

  @MainActor private func setupNowPlaying() {
    let nowPlaying = NowPlayingInfo.shared
  
    let publication = audiobookVM?.navigator.publication

    // Initial publication metadata.
    nowPlaying.media = NowPlayingInfo.Media(
      title: publication?.metadata.title ?? "",
      artist: publication?.metadata.authors.map(\.name).joined(separator: ", "),
      chapterCount: publication?.readingOrder.count
    )

    // Update the artwork after the view model loaded it.
    audiobookVM?.$cover
      .sink { cover in
        nowPlaying.media?.artwork = cover
      }
      .store(in: &subscriptions)
  }

  private func updateNowPlaying(info: MediaPlaybackInfo) {
    let nowPlaying = NowPlayingInfo.shared

    nowPlaying.playback = NowPlayingInfo.Playback(
      duration: info.duration,
      elapsedTime: info.time,
      rate: audiobookVM?.navigator.settings.speed
    )

    nowPlaying.media?.chapterNumber = info.resourceIndex
  }

  private func clearNowPlaying() {
    NowPlayingInfo.shared.clear()
  }
}
