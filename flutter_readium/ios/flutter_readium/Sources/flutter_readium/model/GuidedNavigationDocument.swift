import Foundation
import ReadiumShared

/// A Readium Guided Navigation Document, describing a structured sequence of
/// media-aligned navigation steps for a publication.
///
/// See https://readium.org/guided-navigation/schema/document.schema.json
struct GuidedNavigationDocument: Equatable {
  /// Optional cross-references to related resources, using the Readium Web
  /// Publication Manifest link schema.
  let links: [Link]

  /// The ordered list of guided navigation objects. Contains at least one entry.
  let guided: [GuidedNavigationObject]

  func toJson() -> [String: Any] {
    var res: [String: Any] = [:]
    if !links.isEmpty { res["links"] = links.map { $0.json } }
    res["guided"] = guided.map { $0.toJson() }
    return res
  }

  func toJsonString(pretty: Bool = false) -> String? {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
    guard let data = try? JSONSerialization.data(withJSONObject: toJson(), options: options) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func fromJson(_ json: [String: Any]?) -> GuidedNavigationDocument? {
    guard let json = json else { return nil }

    let linksJson = json["links"] as? [[String: Any]] ?? []
    let links = linksJson.compactMap { Link(json: $0) }

    let guidedJson = json["guided"] as? [[String: Any]] ?? []
    let guided = guidedJson.compactMap { GuidedNavigationObject.fromJson($0) }

    guard !guided.isEmpty else { return nil }

    return GuidedNavigationDocument(links: links, guided: guided)
  }

  static func fromJson(_ jsonString: String) throws -> GuidedNavigationDocument? {
    let data = Data(jsonString.utf8)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    return fromJson(object)
  }
}
