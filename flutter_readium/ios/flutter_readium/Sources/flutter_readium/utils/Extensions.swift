
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
