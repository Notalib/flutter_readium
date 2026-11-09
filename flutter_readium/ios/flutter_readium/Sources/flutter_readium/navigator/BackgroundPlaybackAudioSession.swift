import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Keeps background playback alive through the pause that accompanies an automatic
/// chapter change.
///
/// Readium's shared `AudioSession` deactivates the `AVAudioSession` whenever a
/// navigator reports it stopped playing while the app is inactive (upstream
/// swift-toolkit #306). An automatic track change pauses the player mid-transition,
/// so with the screen locked the session ends at every chapter boundary; the
/// follow-up play keeps its navigator registered, so the shared `start` early-returns
/// and nothing reactivates the session. iOS then suspends the app instead of playing
/// the next track.
///
/// The wrapper drops only the paused report that an automatic pause produces while the
/// app is inactive: a chapter change, a stall, or a recovery rebuild, all of which
/// happen while `isPlaybackIntended` is true. A pause the user asked for (lock screen,
/// headset, Dart `pause()`) clears the intent first, so it still reaches the shared
/// session and releases the `AVAudioSession` as before. Closing the publication still
/// releases it through `end(for:)`.
final class BackgroundPlaybackAudioSession: AudioSessionManaging {
  private let delegate = AudioSession.shared

  /// Read on the thread that reports the player state, so the navigator's plain
  /// `_playbackIntent` flag is what it returns; every writer clears the flag before it
  /// pauses the player, which is what keeps the two in order.
  private let isPlaybackIntended: () -> Bool

  /// `UIApplication.applicationState` is main-thread only, but `didChangePlaying` arrives
  /// on AVFoundation's queue from the `AVPlayer.rate` observer. Hopping to main there is
  /// not safe either way: `DispatchQueue.main.sync` deadlocks when main is inside
  /// `replaceCurrentItem` or `seek` waiting on that same queue (the hang fixed in
  /// `goBounded`), and an async hop can reorder a paused report after the next playing
  /// one, leaving the shared session believing it is paused. So the state is mirrored
  /// here from the app lifecycle notifications and read under a lock.
  private let stateLock = NSLock()
  private var _isAppActive: Bool
  private var lifecycleObservers: [NSObjectProtocol] = []

  @MainActor
  init(isPlaybackIntended: @escaping () -> Bool) {
    self.isPlaybackIntended = isPlaybackIntended
    _isAppActive = UIApplication.shared.applicationState == .active

    let center = NotificationCenter.default
    lifecycleObservers = [
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.setAppActive(true) },
      center.addObserver(
        forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.setAppActive(false) },
    ]
  }

  deinit {
    lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
  }

  func start(with user: AudioSessionUser, isPlaying: Bool) {
    delegate.start(with: user, isPlaying: isPlaying)
  }

  func end(for user: AudioSessionUser) {
    delegate.end(for: user)
  }

  /// Forwards synchronously on the reporting thread; see `stateLock` for why no hop.
  func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {
    if !isPlaying, !isAppActive, isPlaybackIntended() {
      return
    }
    delegate.user(user, didChangePlaying: isPlaying)
  }

  private var isAppActive: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return _isAppActive
  }

  private func setAppActive(_ isActive: Bool) {
    stateLock.lock()
    _isAppActive = isActive
    stateLock.unlock()
  }
}
