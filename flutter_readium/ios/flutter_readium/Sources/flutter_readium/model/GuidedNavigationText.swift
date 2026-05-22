import Foundation

/// Text associated with a guided navigation object or description.
///
/// Can be either a plain string or a structured object with optional SSML
/// markup and BCP 47 language tag.
///
/// See https://readium.org/guided-navigation/schema/text.schema.json
enum GuidedNavigationText: Equatable {
  case string(String)
  case object(plain: String?, ssml: String?, language: String?)

  /// Parses a [GuidedNavigationText] from its JSON representation.
  ///
  /// Accepts either a String or a dictionary with at least one of `plain` or `ssml`.
  static func fromJson(_ json: Any?) -> GuidedNavigationText? {
    if let s = json as? String {
      return s.isEmpty ? nil : .string(s)
    }
    if let obj = json as? [String: Any] {
      let plain = obj["plain"] as? String
      let ssml = obj["ssml"] as? String
      let language = obj["language"] as? String
      guard plain != nil || ssml != nil else { return nil }
      return .object(plain: plain, ssml: ssml, language: language)
    }
    return nil
  }

  func toJson() -> Any {
    switch self {
    case .string(let s):
      return s
    case .object(let plain, let ssml, let language):
      var res: [String: Any] = [:]
      if let plain = plain { res["plain"] = plain }
      if let ssml = ssml { res["ssml"] = ssml }
      if let language = language { res["language"] = language }
      return res
    }
  }
}
