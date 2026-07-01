import Foundation

/// Alternative description for a guided navigation object, using one or more
/// media references.
///
/// At least one of audioref, imgref, textref, videoref, or text must be present.
///
/// See https://readium.org/guided-navigation/schema/description.schema.json
struct GuidedNavigationDescription: Equatable {
  let audioref: String?
  let imgref: String?
  let textref: String?
  let videoref: String?
  let text: GuidedNavigationText?

  func toJson() -> [String: Any] {
    var res: [String: Any] = [:]
    if let audioref = audioref { res["audioref"] = audioref }
    if let imgref = imgref { res["imgref"] = imgref }
    if let textref = textref { res["textref"] = textref }
    if let videoref = videoref { res["videoref"] = videoref }
    if let text = text { res["text"] = text.toJson() }
    return res
  }

  static func fromJson(_ json: [String: Any]?) -> GuidedNavigationDescription? {
    guard let json = json else { return nil }

    let audioref = json["audioref"] as? String
    let imgref = json["imgref"] as? String
    let textref = json["textref"] as? String
    let videoref = json["videoref"] as? String
    let text = GuidedNavigationText.fromJson(json["text"])

    guard audioref != nil || imgref != nil || textref != nil
            || videoref != nil || text != nil else {
      return nil
    }

    return GuidedNavigationDescription(
      audioref: audioref,
      imgref: imgref,
      textref: textref,
      videoref: videoref,
      text: text
    )
  }
}
