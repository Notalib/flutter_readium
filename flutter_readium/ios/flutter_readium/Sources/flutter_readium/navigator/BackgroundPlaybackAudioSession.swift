import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Keeps the `AVAudioSession` active through automatic pauses while the app is in the
/// background.
///
/// Readium's shared `AudioSession` ends the `AVAudioSession` whenever a navigator reports it
/// stopped playing while the app is inactive, and a later `play()` on the same navigator does
/// not reactivate it until the player's rate actually changes. Automatic track changes,
/// stalls and recovery rebuilds all pause the player briefly, so with the screen locked the
/// session is released at every chapter boundary. Usually the next track starts fast enough
/// that nothing is heard; when it is slow, typically a stream on a poor connection, iOS can
/// suspend the app in the gap and the book stops (NOTA-13449).
///
/// The wrapper drops the paused report only while `isPlaybackIntended` is true. A pause the
/// user asked for clears the intent first, so it still releases the session, and closing the
/// publication still releases it through `end(for:)`.
final class BackgroundPlaybackAudioSession: AudioSessionManaging {
  private let delegate = AudioSession.shared

  /// Called on the thread that reports the player state. Every writer clears the navigator's
  /// intent flag before pausing the player, which keeps the two in order.
  private let isPlaybackIntended: () -> Bool

  /// `UIApplication.applicationState` is main-thread only, but `didChangePlaying` arrives on
  /// AVFoundation's queue. `DispatchQueue.main.sync` from there deadlocks while main waits on
  /// that queue inside `replaceCurrentItem` or `seek` (the hang fixed in `goBounded`), and an
  /// async hop can reorder a paused report after the next playing one. So the state is
  /// mirrored from the lifecycle notifications and read under a lock.
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

  /// Forwards synchronously on the reporting thread; see `stateLock`.
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
