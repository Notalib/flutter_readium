import ReadiumShared

public enum TimebasedState: String {
  case playing
  case loading
  case paused
  case ended
  case failure
}

public class ReadiumTimebasedState : Equatable {
  
  var state: TimebasedState
  var currentOffset: TimeInterval?
  var currentBuffered: TimeInterval?
  var currentDuration: TimeInterval?
  var currentLocator: Locator?

  init(
    state: TimebasedState,
    currentOffset: TimeInterval? = nil,
    currentBuffered: TimeInterval? = nil,
    currentDuration: TimeInterval? = nil,
    currentLocator: Locator? = nil
  ) {
    self.state = state
    self.currentOffset = currentOffset
    self.currentBuffered = currentBuffered
    self.currentDuration = currentDuration
    self.currentLocator = currentLocator
  }

  func toJson() -> [String: Any] {
    var map: [String: Any] = [
      "state": state.rawValue
    ]

    if let currentOffset = currentOffset {
      map["currentOffset"] = Int(currentOffset * 1000)
    }
    if let currentBuffered = currentBuffered {
      map["currentBuffered"] = Int(currentBuffered * 1000)
    }
    if let currentDuration = currentDuration {
      map["currentDuration"] = Int(currentDuration * 1000)
    }
    if let locator = currentLocator {
      map["currentLocator"] = locator.jsonString
    }

    return map
  }

  func toJsonString(pretty: Bool = false) -> String? {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
    guard let data = try? JSONSerialization.data(withJSONObject: toJson(), options: options) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public static func == (lhs: ReadiumTimebasedState, rhs: ReadiumTimebasedState) -> Bool {
    return lhs.state == rhs.state &&
    lhs.currentOffset == rhs.currentOffset &&
    lhs.currentBuffered == rhs.currentBuffered &&
    lhs.currentDuration == rhs.currentDuration &&
    lhs.currentLocator == rhs.currentLocator
  }
}
