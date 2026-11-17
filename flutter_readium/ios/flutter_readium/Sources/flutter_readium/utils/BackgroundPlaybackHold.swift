import UIKit

/// Keeps the app running across a gap in background playback.
///
/// iOS suspends a backgrounded audio app a few seconds after its player stops, even with an
/// active audio session. The player is stopped while the next resource loads and while it is
/// stalled. A background task covers that gap for about 30 seconds; iOS sets the limit.
final class BackgroundPlaybackHold {
  private var task: UIBackgroundTaskIdentifier = .invalid
  private var baselineIndex = 0
  private var baselineTime: TimeInterval = 0

  deinit {
    if task != .invalid {
      let task = task
      DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) }
    }
  }

  private func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  /// Starts the hold at the given playback position. Does nothing while a hold is active.
  func hold(resourceIndex: Int, time: TimeInterval) {
    onMain { [weak self] in
      guard let self, self.task == .invalid else { return }
      self.baselineIndex = resourceIndex
      self.baselineTime = time
      self.task = UIApplication.shared.beginBackgroundTask(withName: "flutter_readium.playback-gap") { [weak self] in
        self?.end()
      }
    }
  }

  /// Ends the hold once playback has moved past the position where it started.
  func releaseIfAdvanced(resourceIndex: Int, time: TimeInterval) {
    onMain {
      guard self.task != .invalid,
            playbackAdvancedPastGap(
              fromResourceIndex: self.baselineIndex, time: self.baselineTime,
              toResourceIndex: resourceIndex, time: time)
      else { return }
      self.end()
    }
  }

  func release() {
    onMain { self.end() }
  }

  private func end() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }
}

/// True when audio is audibly playing again after a gap that started at the `from` position.
/// A new resource counts once it is past its first half second.
func playbackAdvancedPastGap(
  fromResourceIndex: Int, time fromTime: TimeInterval,
  toResourceIndex: Int, time toTime: TimeInterval
) -> Bool {
  toResourceIndex == fromResourceIndex ? toTime > fromTime + 0.5 : toTime > 0.5
}

/// True when buffered audio covers `time` and at least `minimum` seconds after it, so a
/// stalled player can resume without stalling again at once.
func hasBufferedAudio(after time: TimeInterval, in ranges: [Range<Double>], minimum: TimeInterval = 1.0) -> Bool {
  ranges.contains { $0.lowerBound <= time + 0.1 && $0.upperBound >= time + minimum }
}
