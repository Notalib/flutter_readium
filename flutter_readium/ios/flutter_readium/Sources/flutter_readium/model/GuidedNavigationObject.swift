import Foundation

/// A single step in a guided navigation sequence.
///
/// Must contain at least one of: audioref, imgref, textref, videoref, text, or children.
///
/// See https://readium.org/guided-navigation/schema/object.schema.json
struct GuidedNavigationObject: Equatable {
  let id: String?
  let audioref: String?
  let imgref: String?
  let textref: String?
  let videoref: String?
  let text: GuidedNavigationText?
  let role: [GuidedNavigationRole]
  let children: [GuidedNavigationObject]
  let description: GuidedNavigationDescription?

  func toJson() -> [String: Any] {
    var res: [String: Any] = [:]
    if let id = id { res["id"] = id }
    if let audioref = audioref { res["audioref"] = audioref }
    if let imgref = imgref { res["imgref"] = imgref }
    if let textref = textref { res["textref"] = textref }
    if let videoref = videoref { res["videoref"] = videoref }
    if let text = text { res["text"] = text.toJson() }
    if !role.isEmpty { res["role"] = role.map { $0.rawValue } }
    if !children.isEmpty { res["children"] = children.map { $0.toJson() } }
    if let description = description { res["description"] = description.toJson() }
    return res
  }

  static func fromJson(_ json: [String: Any]?) -> GuidedNavigationObject? {
    guard let json = json else { return nil }

    let id = json["id"] as? String
    let audioref = json["audioref"] as? String
    let imgref = json["imgref"] as? String
    let textref = json["textref"] as? String
    let videoref = json["videoref"] as? String
    let text = GuidedNavigationText.fromJson(json["text"])

    let roleStrings = json["role"] as? [String] ?? []
    let role = roleStrings.compactMap { GuidedNavigationRole(rawValue: $0) }

    let childrenJson = json["children"] as? [[String: Any]] ?? []
    let children = childrenJson.compactMap { GuidedNavigationObject.fromJson($0) }

    let description = GuidedNavigationDescription.fromJson(json["description"] as? [String: Any])

    guard audioref != nil || imgref != nil || textref != nil
            || videoref != nil || text != nil || !children.isEmpty else {
      return nil
    }

    return GuidedNavigationObject(
      id: id,
      audioref: audioref,
      imgref: imgref,
      textref: textref,
      videoref: videoref,
      text: text,
      role: role,
      children: children,
      description: description
    )
  }

  static func fromJsonArray(_ json: [[String: Any]]?) -> [GuidedNavigationObject] {
    return (json ?? []).compactMap { GuidedNavigationObject.fromJson($0) }
  }
}
