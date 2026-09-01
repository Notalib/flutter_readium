import Combine
import Flutter
import Foundation
import MediaPlayer
import ReadiumShared
import ReadiumNavigator

public class FlutterAudioNavigator: FlutterTimebasedNavigator, AudioNavigatorDelegate
{
  internal var _publication: Publication
  internal var _initialLocator: Locator?
  internal var _preferences: FlutterAudioPreferences
  internal var _lastTimebasedPlayerState: ReadiumTimebasedState?
  /// Resource index `.ended` was last submitted for. AVPlayer's `timeControlStatus` can
  /// settle to `.paused` a few milliseconds after `shouldPlayNextResource` reports the
  /// resource finished, and that trailing update still flows through the throttled
  /// `$playback` pipeline — without this guard it silently overwrites `.ended`.
  private var _endedResourceIndex: Int?
  internal var _nowPlayingUpdater: NowPlayingInfoUpdater
  @MainActor internal var _audioNavigator: AudioNavigator?

  internal var subscriptions: Set<AnyCancellable> = []

  @Published var cover: UIImage?
  @Published var playback: MediaPlaybackInfo = .init()
  @Published var audioLocator: Locator?

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
      return self.audioLocator
    }
  }

  public var listener: (any TimebasedListener)?

  public init(publication: Publication, preferences: FlutterAudioPreferences, initialLocator: Locator?) {
    self._publication = publication
    self._preferences = preferences
    self._nowPlayingUpdater = NowPlayingInfoUpdater(
      withPublication: publication,
      infoType: preferences.controlPanelInfoType,
      timebase: preferences.controlPanelTimebase
    )
    self._initialLocator = resolveLocator(initialLocator)
  }

  public func initNavigator() async throws -> Void {
    let navigator = makeAudioNavigator(initialLocation: initialLocator)
    if _disposed {
      navigator.delegate = nil
      return
    }
    _audioNavigator = navigator

    self.setupNavigatorStateListeners()
    self.startStallWatchdog()

    Task {
      cover = try? await publication.cover().get()
    }
  }

  @MainActor
  private func makeAudioNavigator(initialLocation: Locator?) -> AudioNavigator {
    let navigator = AudioNavigator(
      publication: publication,
      initialLocation: initialLocation,
      config: AudioNavigator.Configuration(
        preferences: AudioPreferences(fromFlutterPrefs: _preferences),
        playbackRefreshInterval: _preferences.updateIntervalSecs,
      )
    )
    navigator.delegate = self
    return navigator
  }

  private func setupNavigatorStateListeners() {
    /// Subscribe to changes
    $playback
      .throttle(for: .seconds(self._preferences.updateIntervalSecs), scheduler: RunLoop.main, latest: true)
      .sink { [weak self] info in
        guard let self = self else {
          return
        }
        Log.navigator.debug("$playback updated: state=\(info.state),index=\(info.resourceIndex),time=\(info.time),progress=\(info.progress)")

        self.submitTimebasedPlayerStateToListener(info: info, location: _audioNavigator?.currentLocation)
      }
      .store(in: &subscriptions)
  }

  public func dispose() -> Void {
    _disposed = true
    _playbackIntent = false
    _recoveryTask?.cancel()
    _recoveryTask = nil
    _stallWatchdogTask?.cancel()
    _stallWatchdogTask = nil
    if (self._audioNavigator != nil) {
      self._audioNavigator?.pause()
      self._audioNavigator?.delegate = nil
      self._audioNavigator = nil
      self.listener?.timebasedNavigator(self, didChangeState: .init(state: .none))
    }
    self.listener = nil
    self.subscriptions.forEach { $0.cancel() }
    _nowPlayingUpdater.clearNowPlaying()
  }

  public func play(fromLocator: Locator?) async -> Void {
    if _disposed {
      return
    }
    _playbackIntent = true
    if _hasFailed {
      _hasFailed = false
      _recoveryTask?.cancel()
      _recoveryTask = nil
      guard await rebuildNavigator(at: resolveLocator(fromLocator) ?? audioLocator) else {
        return
      }
    } else if let locator = resolveLocator(fromLocator) {
      let _ = await seek(toLocator: locator)
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
    _playbackIntent = false
    _audioNavigator?.pause()
  }

  public func resume() async -> Void {
    if _disposed {
      return
    }
    _playbackIntent = true
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
    await seekRelative(byOffsetSeconds: self._preferences.seekInterval)
  }

  public func seekBackward() async -> Bool {
    await seekRelative(byOffsetSeconds: -1 * self._preferences.seekInterval)
  }

  private static let goToLocatorTimeoutSeconds: UInt64 = 10

  /// Upstream `AudioNavigator.go(to:)` never returns when jumping to a different track while
  /// paused — the player switches track but the call hangs, which would hang the method-channel
  /// result forever. Bounded so the caller always gets an answer; `false` means "not confirmed".
  internal func goBounded(to locator: Locator) async -> Bool {
    guard let navigator = _audioNavigator else { return false }
    guard let navigated = await withTimeout(seconds: Self.goToLocatorTimeoutSeconds, {
      await navigator.go(to: locator)
    }) else {
      Log.navigator.warn("go(to:) timed out after \(Self.goToLocatorTimeoutSeconds)s, treating as failed")
      return false
    }
    return navigated
  }

  public func seek(toLocator: Locator) async -> Bool {
    guard let resolvedLocator = resolveLocator(toLocator) else {
      Log.navigator.warn("Could not resolve Locator: \(toLocator)")
      return false
    }
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    let navigated = await goBounded(to: resolvedLocator)
    if (wasPlaying && navigated) {
      _audioNavigator?.play()
    }
    return navigated
  }

  public func seek(toProgression: Double) async -> Bool {
    if let locator = audioLocator,
       let timeOffset = getTimeOffsetForLocatorWithProgression(locator: locator, progression: toProgression) {
      /// Modify time offset  of current Locator to match desired progression.
      return await self.seek(toOffset: timeOffset)
    }
    return false
  }

  /// Progression is relative to the track the locator points at, so the duration must
  /// come from that track. This used to shadow the parameter with `audioLocator`, which
  /// scaled by the *currently playing* track instead — wrong for any cross-track jump,
  /// and nil at cold open, which then fell back to a start-of-track seek.
  private func getTimeOffsetForLocatorWithProgression(locator: Locator, progression: Double) -> Double? {
    guard let link = publication.readingOrder.firstWithHREF(locator.href),
          let duration = link.duration, duration.isFinite else {
      return nil
    }
    return duration * progression
  }

  public func seek(toOffset: Double) async -> Bool {
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    await _audioNavigator?.seek(to: toOffset)
    if (wasPlaying) {
      _audioNavigator?.play()
    }
    return true
  }

  @MainActor
  public func seek(toPublicationOffset: Double) async -> Bool {
    guard let currentLocator = _audioNavigator?.currentLocation,
          let target = resolvePublicationOffsetTarget(toPublicationOffset) else {
      return false
    }

    if target.readingOrderIndex == playback.resourceIndex {
      return await seek(toOffset: target.offsetSeconds)
    }

    guard let targetLocator = makeAudioLocator(from: currentLocator, target: target) else {
      return false
    }

    return await seek(toLocator: targetLocator)
  }

  public func seekRelative(byOffsetSeconds: Double) async -> Bool {
    if !_preferences.continuousSeeking {
      await _audioNavigator?.seek(by: byOffsetSeconds)
      return true
    }

    if byOffsetSeconds < 0 {
      return await rewindBy(seconds: abs(byOffsetSeconds))
    } else {
      return await fastForwardBy(seconds: byOffsetSeconds)
    }
  }

  private func rewindBy(seconds rewindSeconds: TimeInterval) async -> Bool {
    guard let audioNavigator = _audioNavigator else {
      return false
    }

    let info = audioNavigator.playbackInfo
    let currentIndex = info.resourceIndex

    let durations = audioDurations(
      currentIndex: currentIndex,
      currentDuration: info.duration
    )

    guard let target = AudioSeekPolicy.resolveRewindTarget(
      currentIndex: currentIndex,
      currentOffsetSeconds: info.time,
      rewindSeconds: rewindSeconds,
      durations: durations
    ) else {
      return false
    }

    return await seek(
      to: target,
      currentIndex: currentIndex,
      currentLocator: audioNavigator.currentLocation
    )
  }

  private func fastForwardBy(seconds fastForwardSeconds: TimeInterval) async -> Bool {
    guard let audioNavigator = _audioNavigator else {
      return false
    }

    let info = audioNavigator.playbackInfo
    let currentIndex = info.resourceIndex

    let durations = audioDurations(
      currentIndex: currentIndex,
      currentDuration: info.duration
    )

    guard let target = AudioSeekPolicy.resolveFastForwardTarget(
      currentIndex: currentIndex,
      currentOffsetSeconds: info.time,
      fastForwardSeconds: fastForwardSeconds,
      durations: durations
    ) else {
      return false
    }

    return await seek(
      to: target,
      currentIndex: currentIndex,
      currentLocator: audioNavigator.currentLocation
    )
  }

  private func audioDurations(
    currentIndex: Int,
    currentDuration: TimeInterval?
  ) -> [TimeInterval?] {
    var durations: [TimeInterval?] = publication.readingOrder.map { link in
      link.duration
    }

    if durations.indices.contains(currentIndex), durations[currentIndex] == nil {
      durations[currentIndex] = currentDuration
    }

    return durations
  }

  private func seek(
    to target: AudioSeekPolicy.Target,
    currentIndex: Int,
    currentLocator: Locator?
  ) async -> Bool {
    if target.readingOrderIndex == currentIndex {
      return await seek(toOffset: target.offsetSeconds)
    }

    guard let currentLocator else {
      return false
    }

    guard let targetLocator = makeAudioLocator(
      from: currentLocator,
      target: target
    ) else {
      return false
    }

    return await seek(toLocator: targetLocator)
  }

  private func makeAudioLocator(
    from currentLocator: Locator,
    target: AudioSeekPolicy.Target
  ) -> Locator? {
    guard publication.readingOrder.indices.contains(target.readingOrderIndex) else {
      return nil
    }

    let link = publication.readingOrder[target.readingOrderIndex]

    var locator = currentLocator.copy(href: link.url())

    locator.locations.position = target.readingOrderIndex + 1
    locator.locations.progression = nil
    locator.locations.totalProgression = nil
    locator.locations.otherLocations.removeValue(forKey: "tocHref")
    locator.locations.otherLocations.removeValue(forKey: "tocId")

    locator = locator.copyWithOffset(target.offsetSeconds)

    return locator
  }

  // MARK: AudioNavigatorDelegate

  /// Called when the playback updates.
  public func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    if info.state == .paused,
       info.progress >= 1.0,
       info.resourceIndex == self.publication.manifest.readingOrder.count - 1 {
      _playbackIntent = false
    }
    self._nowPlayingUpdater.updatePlaybackFromInfo(info, withSpeedSetting: _audioNavigator?.settings.speed)
    self._nowPlayingUpdater.updateCommandCenterControls()
    self.playback = info
  }

  public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
    self.audioLocator = locator
    // Submit new locator to the listener
    self.submitAudioLocatorReachedToListener(locator)

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
  ///
  /// Fires from `AVPlayerItemDidPlayToEndTime`, before any auto-advance — this is the
  /// authoritative "resource finished" signal (mirrors the web bridge's `trackEnded`).
  /// When there's no next resource, the publication has ended: submit `.ended` directly
  /// here rather than relying on `info.progress >= 1.0` in the throttled `$playback`
  /// pipeline, since AVPlayer's reported currentTime at end-of-track is rarely exactly
  /// equal to the resource duration.
  public func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    if !canGoForward {
      Log.navigator.info("Resource \(info.resourceIndex) finished — no next resource, publication ended")
      submitEndedStateToListener(info: info)
    } else {
      Log.navigator.debug("Resource \(info.resourceIndex) finished, advancing to next resource")
    }
    return true
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, presentError error: ReadiumNavigator.NavigatorError) {
    Log.navigator.error("Should present error: \(error)")
    // TODO: LCP related errors, ignored until supporting LCP.
  }

  public func navigator(_ navigator: any ReadiumNavigator.Navigator, didFailToLoadResourceAt href: ReadiumShared.RelativeURL, withError error: ReadiumShared.ReadError) {
    self.listener?.timebasedNavigator(self, encounteredError: error, withDescription: "DidFailToLoadResourceAt: \(href)")
  }

  // MARK: AudioNavigator specific API

  @MainActor
  func setAudioPreferences(_ preferences: FlutterAudioPreferences) {
    self._preferences = preferences
    self._nowPlayingUpdater.infoType = preferences.controlPanelInfoType
    self._nowPlayingUpdater.timebase = preferences.controlPanelTimebase

    if let info = self._audioNavigator?.playbackInfo {
      self._nowPlayingUpdater.updatePlaybackFromInfo(
        info,
        withSpeedSetting: self._audioNavigator?.settings.speed
      )
    }

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

  @MainActor
  public func decorationsUpdated() -> Void {
    // No decorations for AudioNavigator
  }

  // MARK: Internal AudioNavigator API

  internal var _recoveryTask: Task<Void, Never>?
  /// Snapshotted at construction time from `AudioRecoveryPolicy.current` -
  /// per the plugin's "no mid-stream reconfiguration" contract, a policy
  /// change via `setAudioRecoveryPolicy` only takes effect for the
  /// next-opened publication.
  internal let _recoveryPolicy = AudioRecoveryPolicy.current
  /// Terminal-failure latch. Must be an explicit flag: inferring it from
  /// `_lastTimebasedPlayerState` is unreliable, as rebuilt navigators emit
  /// paused/loading states that would overwrite a `.failure` there.
  internal var _hasFailed = false
  /// Set in `dispose`; prevents recovery/rebuild from installing a fresh player
  /// after the publication was closed.
  internal var _disposed = false
  /// User/app playback intent. iOS exposes only `.paused/.playing/.loading`, so
  /// this mirrors Android's `playWhenReady` for stall-watchdog decisions.
  internal var _playbackIntent = false
  /// Stall watchdog task - see `startStallWatchdog`. Cancelled/restarted on rebuild.
  internal var _stallWatchdogTask: Task<Void, Never>?

  /// Entry point for resource read errors routed from the plugin.
  @MainActor
  public func handleResourceReadError(href: AnyURL, error: ReadError) {
    /// Only react to failures of this publication's audio resources.
    guard publication.readingOrder.firstWithHREF(href) != nil else {
      Log.navigator.warn("Ignoring read error for href not in readingOrder: \(href) — \(error)")
      return
    }
    /// Already in terminal failure — client must call play() to retry.
    if _hasFailed {
      return
    }

    switch error.audioStreamAction {
    case .ignore:
      Log.navigator.debug("Ignoring audio resource read error for \(href): \(error)")
      return
    case let .fail(code, reason):
      Log.navigator.warn("Audio resource read error classified as terminal [\(code)] for \(href): \(error)")
      enterFailureState(
        error: error, code: code, href: href.string, httpStatus: error.httpStatus, reason: reason,
        description: "Resource read failed: \(href)")
    case .retry:
      Log.navigator.warn("Audio resource read error classified as retryable for \(href): \(error)")
      startRecovery(href: href, error: error, terminalCode: "AudioStreamNetworkError")
    }
  }

  /// - Parameter terminalCode: Code to use if recovery exhausts its attempts, carried
  ///   through from how `error` was originally classified (e.g. `AudioStreamNetworkError`
  ///   for a classified network error, or a stall-specific code) — not the generic
  ///   `AudioStreamError` fallback.
  @MainActor
  private func startRecovery(href: AnyURL, error: Error, terminalCode: String) {
    guard !_disposed else {
      return
    }
    guard _recoveryTask == nil else {
      return  // recovery already in progress
    }
    let resumeLocator = (audioLocator ?? _audioNavigator?.currentLocation)?.copyWithOffset(playback.time)

    _recoveryTask = Task { @MainActor in
      defer { _recoveryTask = nil }

      for attempt in 1..._recoveryPolicy.maxAttempts {
        sendErrorEvent(
          code: "AudioStreamRetry",
          message: error.localizedDescription,
          data: [
            "href": href.string,
            "attempt": attempt,
            "maxAttempts": self._recoveryPolicy.maxAttempts,
          ])
        submitRecoveryState(.loading, locator: resumeLocator)

        try? await Task.sleep(nanoseconds: UInt64(self._recoveryPolicy.delay(forAttempt: attempt) * 1_000_000_000))
        if Task.isCancelled { return }

        guard await rebuildNavigator(at: resumeLocator) else {
          continue
        }

        // connectionTimeoutSeconds is the policy knob for how long each attempt
        // gets to prove playback advanced (Android/web share this meaning).
        if await playbackAdvanced(withinSeconds: self._recoveryPolicy.connectionTimeoutSeconds) {
          return  // recovered — regular state emissions resume via delegate
        }
      }

      enterFailureState(
        error: error,
        code: terminalCode,
        href: href.string,
        httpStatus: (error as? ReadError)?.httpStatus,
        description: "Recovery failed after \(self._recoveryPolicy.maxAttempts) attempts: \(href)")
    }
  }

  /// Tears down and rebuilds the upstream navigator. Required for recovery:
  /// upstream never replaces a failed AVPlayerItem for the same resource index.
  @MainActor
  private func rebuildNavigator(at locator: Locator?) async -> Bool {
    guard !_disposed else {
      return false
    }
    _audioNavigator?.pause()
    _audioNavigator?.delegate = nil
    let navigator = makeAudioNavigator(initialLocation: locator ?? initialLocator)
    guard !_disposed else {
      navigator.delegate = nil
      return false
    }
    _audioNavigator = navigator
    navigator.play()
    startStallWatchdog()
    return true
  }

  /// True once [offsetAdvanced] within `timeout`. Called from `startRecovery` with
  /// `connectionTimeoutSeconds` — the window each recovery attempt gets to prove
  /// playback advanced. (`state == .playing` alone is unreliable: with
  /// `automaticallyWaitsToMinimizeStalling = false` a stalled player can report a
  /// playing timeControlStatus.)
  @MainActor
  private func playbackAdvanced(withinSeconds timeout: TimeInterval) async -> Bool {
    let startTime = playback.time
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !Task.isCancelled {
      if offsetAdvanced(sinceTime: startTime) {
        return true
      }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return false
  }

  /// True when playback is `.playing` and its time has moved past `sinceTime` by more
  /// than 0.1s. Shared by `playbackAdvanced` (post-rebuild recovery verification) and
  /// `startStallWatchdog` (stall detection) so both agree on what "playback is actually
  /// progressing" means.
  @MainActor
  private func offsetAdvanced(sinceTime: TimeInterval) -> Bool {
    playback.state == .playing && playback.time > sinceTime + 0.1
  }

  /// Stall watchdog: today's recovery is error-driven only (resource read errors via
  /// `handleResourceReadError`), so a *throttled* (not dropped) connection that keeps
  /// bytes trickling in never errors and playback sits in Buffering/Loading forever.
  /// This polls the playback offset once a second and, if playback intent is on
  /// (`timeControlStatus`/state indicates playing) but the offset hasn't advanced within
  /// `AudioRecoveryPolicy.stallTimeoutSeconds`, synthesizes a retryable `ReadError` into
  /// the same `startRecovery` path a real resource read error would take.
  ///
  /// Skips while already recovering/terminally failed, or while playback isn't intended
  /// (paused/ended) — those aren't stalls. Cancelled and restarted whenever the navigator
  /// is rebuilt.
  @MainActor
  private func startStallWatchdog() {
    _stallWatchdogTask?.cancel()
    _stallWatchdogTask = Task { @MainActor in
      var lastAdvanceTime = playback.time
      var deadline = Date().addingTimeInterval(self._recoveryPolicy.stallTimeoutSeconds)

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        if _recoveryTask != nil || _hasFailed {
          lastAdvanceTime = playback.time
          deadline = Date().addingTimeInterval(self._recoveryPolicy.stallTimeoutSeconds)
          continue
        }

        guard _playbackIntent, playback.state != .paused else {
          // Genuinely not trying to play (paused/ended) — not a stall, reset the
          // window. `.loading` with playback intent is NOT reset here: a network
          // stall sits there, so it must count toward the deadline.
          lastAdvanceTime = playback.time
          deadline = Date().addingTimeInterval(self._recoveryPolicy.stallTimeoutSeconds)
          continue
        }

        if offsetAdvanced(sinceTime: lastAdvanceTime) {
          lastAdvanceTime = playback.time
          deadline = Date().addingTimeInterval(self._recoveryPolicy.stallTimeoutSeconds)
          continue
        }

        if Date() >= deadline {
          Log.navigator.warn("Playback stalled: offset didn't advance within \(self._recoveryPolicy.stallTimeoutSeconds)s, synthesizing retryable error")
          guard let href = (audioLocator ?? _audioNavigator?.currentLocation)?.href else {
            return
          }
          // .other is the toolkit's documented extension point for non-toolkit-originated
          // errors — used here for a plugin-synthesized stall, not a real read failure.
          startRecovery(
            href: href,
            error: ReadError.access(.other(DebugError("Playback stalled: offset didn't advance within \(self._recoveryPolicy.stallTimeoutSeconds)s"))),
            terminalCode: "AudioStreamNetworkError")
          return  // startRecovery owns the retry loop; a fresh watchdog starts on rebuild
        }
      }
    }
  }

  @MainActor
  internal func enterFailureState(
    error: Error, code: String, href: String? = nil, httpStatus: Int? = nil, reason: ReadiumErrorReason? = nil, description: String
  ) {
    Log.navigator.error("Audio streaming failure [\(code)]: \(description) — \(error)")
    _hasFailed = true
    _playbackIntent = false
    _recoveryTask?.cancel()
    _stallWatchdogTask?.cancel()
    _stallWatchdogTask = nil
    /// Tear down so the failed player stops issuing resource reads and
    /// emitting states. play() rebuilds from the last locator.
    _audioNavigator?.pause()
    _audioNavigator?.delegate = nil
    _audioNavigator = nil
    var data: [String: Any] = [:]
    if let href { data["href"] = href }
    if let httpStatus { data["httpStatus"] = httpStatus }
    if let reason { data["reason"] = reason.rawValue }
    sendErrorEvent(code: code, message: error.localizedDescription, data: data)
    submitRecoveryState(.failure, locator: audioLocator)
  }

  @MainActor
  private func submitRecoveryState(_ state: TimebasedState, locator: Locator?) {
    var locator = locator
    if locator?.locations.position == nil {
      locator?.locations.position = playback.resourceIndex + 1
    }
    let timebasedState = ReadiumTimebasedState(state: state, currentLocator: locator?.toClientFriendlyLocator())
    if timebasedState != _lastTimebasedPlayerState {
      _lastTimebasedPlayerState = timebasedState
      listener?.timebasedNavigator(self, didChangeState: timebasedState)
    }
  }

  private func sendErrorEvent(code: String, message: String, data: [String: Any]? = nil) {
    FlutterReadiumPlugin.instance?.errorStreamHandler?.sendEvent(
      FlutterReadiumError(message: message, code: code, data: data).toJsonString())
  }

  internal func submitAudioLocatorReachedToListener(_ locator: Locator) {
    var locator = locator
    if locator.locations.position == nil,
       let navigator = self._audioNavigator {
      locator.locations.position = navigator.playbackInfo.resourceIndex + 1
    }
    self.listener?.timebasedNavigator(self, reachedLocator: locator, segmentDuration: nil, isWordRange: false)
  }

  internal func submitTimebasedPlayerStateToListener(info: MediaPlaybackInfo, location: Locator?, bufferedInterval: TimeInterval? = nil) {
    /// While recovery pins .loading (or after terminal failure), suppress the
    /// rebuilt navigators' paused/loading churn — only submitRecoveryState emits.
    if _recoveryTask != nil || _hasFailed {
      return
    }

    if let endedIndex = _endedResourceIndex {
      if info.resourceIndex == endedIndex && info.state == .paused {
        // AVPlayer settling to .paused right after we reported .ended for this resource.
        Log.navigator.debug("Skipped state emission - resource \(endedIndex) already reported ended")
        return
      }
      // Any other transition (new resourceIndex, or .playing/.loading on the same one) means
      // playback moved on for real; stop suppressing.
      _endedResourceIndex = nil
    }

    /// Create TimebasedState and send it over the timebased-state stream.
    let timebasedState = mapToTimebasedState(info: info, location: location, bufferedInterval: bufferedInterval)

    // If state has changed, submit it to listener.
    if (timebasedState != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = timebasedState
      Log.navigator.debug("Submitting state=\(timebasedState.state) resourceIndex=\(info.resourceIndex) progress=\(info.progress)")
      self.listener?.timebasedNavigator(self, didChangeState: timebasedState)
    } else {
      Log.navigator.debug("Skipped state emission - duplicate")
    }
  }

  /// Submits the terminal `.ended` state directly, bypassing the throttled `$playback`
  /// pipeline. See `navigator(_:shouldPlayNextResource:)` for why.
  private func submitEndedStateToListener(info: MediaPlaybackInfo) {
    var locator = audioLocator
    locator?.locations.position = info.resourceIndex + 1
    locator = locator?.toClientFriendlyLocator()
    locator?.locations.totalProgression = 1.0

    let timebasedState = ReadiumTimebasedState(
      state: .ended,
      currentOffset: info.time,
      currentDuration: info.duration,
      totalProgressDuration: makeTotalProgressDuration(locator),
      totalDuration: makePublicationDuration(),
      currentLocator: locator
    )

    _endedResourceIndex = info.resourceIndex

    if (timebasedState != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = timebasedState
      Log.navigator.debug("Submitting state=ended resourceIndex=\(info.resourceIndex) progress=\(info.progress)")
      self.listener?.timebasedNavigator(self, didChangeState: timebasedState)
    } else {
      Log.navigator.debug("Skipped state emission - duplicate")
    }
  }

  internal func resolveLocator(_ locator: Locator?) -> Locator? {
    guard let locator = locator else {
      return nil
    }
    var resolvedLocator = locator
    /// Fix href if not in readingOrder, by using position.
    let readingOrderContainsHref = publication.readingOrder.contains(where: { $0.href == locator.href.string.removingPrefix("/") })
    if readingOrderContainsHref == false,
       let position = locator.locations.position,
       publication.readingOrder.indices.contains(position - 1) {
      resolvedLocator = locator.copy(href: publication.readingOrder[position - 1].url())
    }
    /// Set time offset fragment from progression
    var timeOffset = locator.timeOffset
    /// Progression is resolved to a time fragment here, as this resolution is unique to AudioNavigator.
    // TODO: This should really be handled by the Readium Navigator (upstream issue).
    if let progression = locator.locations.progression, progression.isFinite,
       let preciseTimeOffset = getTimeOffsetForLocatorWithProgression(locator: resolvedLocator, progression: progression) {
        timeOffset = preciseTimeOffset
    }
    resolvedLocator = resolvedLocator.copyWithOffset(timeOffset ?? 0.0)
    return resolvedLocator
  }

  internal func mapToTimebasedState(info: MediaPlaybackInfo, location: Locator?, bufferedInterval: TimeInterval? = nil) -> ReadiumTimebasedState {
    var locator = location

    /// Enrich Locator with position before submitting to listeners.
    if locator != nil {
      locator?.locations.position = info.resourceIndex + 1
      /// Ensure timeOffset is rounded to 2 decimals
      locator = locator?.toClientFriendlyLocator()
    }

    /// Fetch MediaPlaybackState and convert it to TimebasedState.
    let playerState = info.asClientTimebasedState(playbackIntent: _playbackIntent)

    let totalProgressDuration = makeTotalProgressDuration(locator)
    let totalDuration = makePublicationDuration()

    /// Create TimebasedState and send it over the timebased-state stream.
    let timebasedState = ReadiumTimebasedState(
      state: playerState,
      currentOffset: info.time,
      currentBuffered: bufferedInterval,
      currentDuration: info.duration ?? nil,
      totalProgressDuration: totalProgressDuration,
      totalDuration: totalDuration,
      currentLocator: locator
    )
    return timebasedState
  }

  private func makePublicationDuration() -> TimeInterval? {
    computePublicationDuration(publication.readingOrder.map { $0.duration })
  }

  private func resolvePublicationOffsetTarget(_ offsetSeconds: TimeInterval) -> AudioSeekPolicy.Target? {
    let durations = publication.readingOrder.map { $0.duration }
    let validDurations = durations.compactMap { duration -> TimeInterval? in
      guard let duration, duration.isFinite, duration > 0 else {
        return nil
      }
      return duration
    }

    guard validDurations.count == durations.count, !validDurations.isEmpty else {
      return nil
    }

    let publicationDuration = validDurations.reduce(0, +)
    var remaining = min(max(0, offsetSeconds), publicationDuration)

    for (index, duration) in validDurations.enumerated() {
      if remaining <= duration || index == validDurations.indices.last {
        return AudioSeekPolicy.Target(
          readingOrderIndex: index,
          offsetSeconds: min(remaining, duration),
        )
      }
      remaining -= duration
    }

    return nil
  }

  private func makeTotalProgressDuration(_ locator: Locator?) -> TimeInterval? {
    computeTotalProgressDuration(
      totalProgression: locator?.locations.totalProgression,
      publicationDuration: makePublicationDuration()
    )
  }
}

func computePublicationDuration(_ durations: [Double?]) -> TimeInterval? {
  let validDurations = durations.compactMap { duration -> TimeInterval? in
    guard let duration, duration.isFinite, duration > 0 else {
      return nil
    }
    return duration
  }

  if validDurations.count != durations.count || validDurations.isEmpty {
    return nil
  }

  return validDurations.reduce(0, +)
}

func computeTotalProgressDuration(
  totalProgression: Double?,
  publicationDuration: TimeInterval?
) -> TimeInterval? {
  guard let totalProgression,
        totalProgression.isFinite,
        let publicationDuration else {
    return nil
  }

  return min(1.0, max(0.0, totalProgression)) * publicationDuration
}
