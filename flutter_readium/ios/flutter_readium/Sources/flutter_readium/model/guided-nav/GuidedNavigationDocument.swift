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
    if !links.isEmpty { res["links"] = links.map { $0.jsonValue } }
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
    let links = linksJson.compactMap { try? Link(json: JSONValue($0)) }

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

  /// Converts this document to a list of `FlutterMediaOverlay` by flattening all
  /// `GuidedNavigationObject`s that carry both an `audioref` and a `textref`, then
  /// grouping the resulting items by their (audioFile, textFile) pair.
  ///
  /// - Parameters:
  ///   - position: Reading-order position (1-based) shared by all generated items.
  ///   - tocHref: ToC href to attach to every item, or nil if unknown.
  ///   - title: Chapter/section title, supplied by the caller from the publication ToC.
  ///   - readingOrderDuration: Total duration of the reading-order item, used for progression calculations.
  func toMediaOverlays(
    atPosition position: Int = 0,
    atTocHref tocHref: String? = nil,
    title: String = "",
    readingOrderDuration: TimeInterval? = nil
  ) -> [FlutterMediaOverlay] {
    func flatten(_ obj: GuidedNavigationObject) -> [FlutterMediaOverlayItem] {
      var items: [FlutterMediaOverlayItem] = []
      // Accept textref (EPUB/read-aloud) or imgref (Divina panel audio) as the text anchor.
      if let audio = obj.audioref, let text = obj.textref ?? obj.imgref {
        items.append(FlutterMediaOverlayItem(
          audio: audio,
          text: text,
          position: position,
          tocTitle: title.isEmpty ? nil : title,
          tocHref: tocHref,
          readingOrderDuration: readingOrderDuration
        ))
      }
      for child in obj.children {
        items += flatten(child)
      }
      return items
    }

    let allItems = guided.flatMap { flatten($0) }

    // Group by (audioFile, textFile), preserving insertion order.
    var orderedKeys: [(String, String)] = []
    var itemsByKey: [String: [FlutterMediaOverlayItem]] = [:]
    for item in allItems {
      let key = "\(item.audioFile)|\(item.textFile)"
      if itemsByKey[key] == nil {
        orderedKeys.append((item.audioFile, item.textFile))
        itemsByKey[key] = []
      }
      itemsByKey[key]!.append(item)
    }

    return orderedKeys.compactMap { (audioFile, textFile) in
      let key = "\(audioFile)|\(textFile)"
      guard let items = itemsByKey[key], !items.isEmpty else { return nil }
      return FlutterMediaOverlay(items: items, readingOrderDuration: readingOrderDuration)
    }
  }
}
