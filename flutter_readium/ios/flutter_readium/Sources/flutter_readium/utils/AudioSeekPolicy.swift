import Foundation

internal enum AudioSeekPolicy {
  internal struct Target: Equatable {
    /// Zero-based index into `publication.readingOrder`.
    let readingOrderIndex: Int

    /// Offset from the beginning of the target audio resource.
    let offsetSeconds: TimeInterval
  }

  /// Resolves the target for a negative relative seek.
  /// - If the rewind remains inside the current resource, seek normally.
  /// - If the rewind would cross the start of the current resource, cross into previous resources
  ///   by the remaining amount.
  internal static func resolveRewindTarget(
    currentIndex: Int,
    currentOffsetSeconds rawCurrentOffsetSeconds: TimeInterval,
    rewindSeconds rawRewindSeconds: TimeInterval,
    durations: [TimeInterval?]
  ) -> Target? {
    guard durations.indices.contains(currentIndex) else {
      return nil
    }

    guard rawRewindSeconds.isFinite, rawRewindSeconds >= 0 else {
      return nil
    }

    let currentOffsetSeconds = normalizedOffset(
      rawCurrentOffsetSeconds,
      duration: normalizedDuration(durations[currentIndex])
    )

    // Case 1:
    // The rewind target is still inside the current audio file.
    if rawRewindSeconds <= currentOffsetSeconds {
      return Target(
        readingOrderIndex: currentIndex,
        offsetSeconds: currentOffsetSeconds - rawRewindSeconds
      )
    }

    // Case 2:
    // The rewind target crosses the beginning of the current audio file,
    // so we cross into previous audio files by the remaining amount.
    var remainingRewindSeconds = rawRewindSeconds - currentOffsetSeconds
    var targetIndex = currentIndex - 1

    while true {
      guard durations.indices.contains(targetIndex) else {
        return Target(
          readingOrderIndex: 0,
          offsetSeconds: 0
        )
      }

      guard let targetDuration = normalizedDuration(durations[targetIndex]) else {
        return Target(
          readingOrderIndex: targetIndex,
          offsetSeconds: 0
        )
      }

      if remainingRewindSeconds <= targetDuration {
        return Target(
          readingOrderIndex: targetIndex,
          offsetSeconds: targetDuration - remainingRewindSeconds
        )
      }

      if targetIndex == 0 {
        return Target(
          readingOrderIndex: 0,
          offsetSeconds: 0
        )
      }

      remainingRewindSeconds -= targetDuration
      targetIndex -= 1
    }
  }
  
  /// Resolves the target for a positive relative seek.
  /// - If the fast forward remains inside the current resource, seek normally.
  /// - If the fast forward would cross the end of the current resource, cross into following resources
  ///   by the remaining amount.
  internal static func resolveFastForwardTarget(
    currentIndex: Int,
    currentOffsetSeconds rawCurrentOffsetSeconds: TimeInterval,
    fastForwardSeconds rawFastForwardSeconds: TimeInterval,
    durations: [TimeInterval?]
  ) -> Target? {
    guard durations.indices.contains(currentIndex) else {
      return nil
    }
    
    guard rawFastForwardSeconds.isFinite, rawFastForwardSeconds >= 0 else {
      return nil
    }
    
    let currentDuration = normalizedDuration(durations[currentIndex])
    
    let currentOffsetSeconds = normalizedOffset(
      rawCurrentOffsetSeconds,
      duration: currentDuration
    )
    
    // If we do not know the current file duration, we cannot determine whether
    // the fast-forward crosses the end of the current file.
    guard let currentDuration else {
      return Target(
        readingOrderIndex: currentIndex,
        offsetSeconds: currentOffsetSeconds
      )
    }
    
    let remainingDurationInCurrentFile = currentDuration - currentOffsetSeconds
    
    // Case 1:
    // The fast-forward target is still inside the current audio file.
    if rawFastForwardSeconds <= remainingDurationInCurrentFile {
      return Target(
        readingOrderIndex: currentIndex,
        offsetSeconds: currentOffsetSeconds + rawFastForwardSeconds
      )
    }
    
    // Case 2:
    // The fast-forward target crosses the end of the current audio file,
    // so we cross into following audio files by the remaining amount.
    var remainingFastForwardSeconds = rawFastForwardSeconds - remainingDurationInCurrentFile
    var targetIndex = currentIndex + 1
    
    while true {
      guard durations.indices.contains(targetIndex) else {
        let lastIndex = durations.indices.last ?? currentIndex
        let lastDuration = normalizedDuration(durations[lastIndex]) ?? 0
        
        return Target(
          readingOrderIndex: lastIndex,
          offsetSeconds: lastDuration
        )
      }
      
      guard let targetDuration = normalizedDuration(durations[targetIndex]) else {
        return Target(
          readingOrderIndex: targetIndex,
          offsetSeconds: 0
        )
      }
      
      if remainingFastForwardSeconds <= targetDuration {
        return Target(
          readingOrderIndex: targetIndex,
          offsetSeconds: remainingFastForwardSeconds
        )
      }
      
      if targetIndex == durations.count - 1 {
        return Target(
          readingOrderIndex: targetIndex,
          offsetSeconds: targetDuration
        )
      }
      
      remainingFastForwardSeconds -= targetDuration
      targetIndex += 1
    }
  }

  private static func normalizedDuration(
    _ value: TimeInterval?
  ) -> TimeInterval? {
    guard let value, value.isFinite, value >= 0 else {
      return nil
    }

    return value
  }

  private static func normalizedOffset(
    _ value: TimeInterval,
    duration: TimeInterval?
  ) -> TimeInterval {
    guard value.isFinite else {
      return 0
    }

    let lowerBounded = max(0, value)

    guard let duration else {
      return lowerBounded
    }

    return min(lowerBounded, duration)
  }
}

