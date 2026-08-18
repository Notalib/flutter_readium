
func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
  return min(max(value, minValue), maxValue)
}

extension Collection {
  /**
   * Returns the first item which successfully maps
   */
  func firstMap<T>(_ transform: (Element) -> T?) -> T? {
    for element in self {
      if let value = transform(element) {
        return value
      }
    }
    return nil
  }
}

extension Sequence {
  func asyncCompactMap<T>(
    _ transform: (Element) async -> T?
  ) async -> [T] {
    var results: [T] = []
    for element in self {
      if let value = await transform(element) {
        results.append(value)
      }
    }
    return results
  }
}

extension Array {
    /// Splits the array into chunks of the given size.
    /// The last chunk may contain fewer elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Runs `operation`, returning nil if it doesn't finish within `seconds`.
///
/// The timed-out task is not actually cancelled, so only use this on work that is safe to
/// leave running — Readium's JS-evaluation continuations, for one, ignore cancellation.
func withTimeout<T: Sendable>(
  seconds: UInt64,
  _ operation: @escaping @Sendable () async -> T
) async -> T? {
  await withTaskGroup(of: T?.self) { group in
    group.addTask { await operation() }
    group.addTask {
      // Task.sleep(for: .seconds(_:)) would read better but is iOS 16+; the podspec targets 15.0.
      try? await Task.sleep(nanoseconds: seconds * NSEC_PER_SEC)
      return nil
    }
    let first = await group.next() ?? nil
    group.cancelAll()
    return first
  }
}

