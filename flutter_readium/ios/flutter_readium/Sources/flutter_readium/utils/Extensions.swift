import Foundation

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
/// `operation` is cancelled on timeout but not guaranteed to stop — only use this on work
/// that is safe to leave running, e.g. Readium continuations that ignore cancellation.
func withTimeout<T: Sendable>(
  seconds: UInt64,
  _ operation: @escaping @Sendable () async -> T
) async -> T? {
  let once = TimeoutOnceFlag()
  return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
    let work = Task {
      let value = await operation()
      if once.claim() { continuation.resume(returning: value) }
    }
    Task {
      // Task.sleep(for: .seconds(_:)) would read better but is iOS 16+; the podspec targets 15.0.
      try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
      if once.claim() {
        work.cancel()
        continuation.resume(returning: nil)
      }
    }
  }
}

/// Single-use claim so only one of `withTimeout`'s two racing tasks resumes the continuation.
private final class TimeoutOnceFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}

