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
/// Suppressing only that one rule keeps the session active while backgrounded and
/// paused — what background audiobook players do; iOS still suspends the app if no
/// audio is rendering, and closing the publication still releases the session.
final class BackgroundPlaybackAudioSession: AudioSessionManaging {
  static let shared = BackgroundPlaybackAudioSession()

  private let delegate = AudioSession.shared

  func start(with user: AudioSessionUser, isPlaying: Bool) {
    delegate.start(with: user, isPlaying: isPlaying)
  }

  func end(for user: AudioSessionUser) {
    delegate.end(for: user)
  }

  /// Forwards reports synchronously: hopping asynchronously would let a paused
  /// report land after the chapter change's start and end the session anyway.
  func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {
    if !isPlaying, isAppActive == false {
      return
    }
    delegate.user(user, didChangePlaying: isPlaying)
  }

  private var isAppActive: Bool {
    if Thread.isMainThread {
      return UIApplication.shared.applicationState == .active
    }
    return DispatchQueue.main.sync { UIApplication.shared.applicationState == .active }
  }
}
