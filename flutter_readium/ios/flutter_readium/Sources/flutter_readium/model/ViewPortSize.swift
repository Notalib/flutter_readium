import Foundation

public class ViewPortSize: Equatable {
  var width: Int
  var height: Int
  var scrollTop: Int
  var scrollHeight: Int
  var scrollLeft: Int
  var scrollWidth: Int
  var scrollMode: Bool

  init(
    width: Int,
    height: Int,
    scrollTop: Int,
    scrollHeight: Int,
    scrollLeft: Int,
    scrollWidth: Int,
    scrollMode: Bool
  ) {
    self.width = width
    self.height = height
    self.scrollTop = scrollTop
    self.scrollHeight = scrollHeight
    self.scrollLeft = scrollLeft
    self.scrollWidth = scrollWidth
    self.scrollMode = scrollMode
  }

  // MARK: - Computed properties (progressions)

  /// Previous progression when scrolling backwards
  var prevProgression: Double {
    if scrollMode {
      return Double(scrollTop - height) / Double(scrollHeight)
    } else {
      return Double(scrollLeft - width) / Double(scrollWidth)
    }
  }

  /// Current progression (top/left of viewport)
  var progression: Double {
    if scrollMode {
      return Double(scrollTop) / Double(scrollHeight)
    } else {
      return Double(scrollLeft) / Double(scrollWidth)
    }
  }

  /// End progression (bottom/right of viewport)
  var endProgression: Double {
    if scrollMode {
      return Double(scrollTop + height) / Double(scrollHeight)
    } else {
      return Double(scrollLeft + width) / Double(scrollWidth)
    }
  }

  /// Next progression when scrolling forwards
  var nextProgression: Double {
    // Same formula as endProgression in original Kotlin
    return endProgression
  }

  /// Number of pages based on viewport size
  var numberOfPages: Double {
    if scrollMode {
      return Double(scrollHeight) / Double(height)
    } else {
      return Double(scrollWidth) / Double(width)
    }
  }

  // MARK: - JSON

  static func fromJson(_ jsonString: String, scrollMode: Bool) -> ViewPortSize? {
    guard
      let data = jsonString.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    return fromJson(obj, scrollMode: scrollMode)
  }

  static func fromJson(_ json: [String: Any], scrollMode: Bool) -> ViewPortSize {
    let height = json["height"] as? Int ?? 0
    let width = json["width"] as? Int ?? 0
    let scrollHeight = json["scrollHeight"] as? Int ?? 0
    let scrollTop = json["scrollTop"] as? Int ?? 0
    let scrollWidth = json["scrollWidth"] as? Int ?? 0
    let scrollLeft = json["scrollLeft"] as? Int ?? 0

    return ViewPortSize(
      width: width,
      height: height,
      scrollTop: scrollTop,
      scrollHeight: scrollHeight,
      scrollLeft: scrollLeft,
      scrollWidth: scrollWidth,
      scrollMode: scrollMode
    )
  }

  func toJson() -> [String: Any] {
    return [
      "width": width,
      "height": height,
      "scrollTop": scrollTop,
      "scrollHeight": scrollHeight,
      "scrollLeft": scrollLeft,
      "scrollWidth": scrollWidth,
      "scrollMode": scrollMode
    ]
  }

  func toJsonString(pretty: Bool = false) -> String? {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
    guard let data = try? JSONSerialization.data(withJSONObject: toJson(), options: options)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  // MARK: - Equatable

  public static func == (lhs: ViewPortSize, rhs: ViewPortSize) -> Bool {
    return lhs.width == rhs.width &&
      lhs.height == rhs.height &&
      lhs.scrollTop == rhs.scrollTop &&
      lhs.scrollHeight == rhs.scrollHeight &&
      lhs.scrollLeft == rhs.scrollLeft &&
      lhs.scrollWidth == rhs.scrollWidth &&
      lhs.scrollMode == rhs.scrollMode
  }
}
