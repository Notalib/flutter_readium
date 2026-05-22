import Foundation
import ReadiumShared

final class PageInformation {

  let tocId: String?
  let physicalPage: String?
  let cssSelector: String?
  /// 1-based index of the current page within the current resource. Only present
  /// in paginated layouts.
  let currentPage: Int?
  /// Total number of pages within the current resource. Only present in
  /// paginated layouts.
  let totalPages: Int?

  init(tocId: String?, physicalPage: String?, cssSelector: String?, currentPage: Int?, totalPages: Int?) {
    self.tocId = tocId
    self.physicalPage = physicalPage
    self.cssSelector = cssSelector
    self.currentPage = currentPage
    self.totalPages = totalPages
  }

  var otherLocations: [String: JSONValue] {
    var res: [String: JSONValue] = [:]

    if let tocId,
       !tocId.isEmpty {
      res["tocId"] = .string(tocId)
    }

    if let physicalPage,
       !physicalPage.isEmpty {
      res["physicalPage"] = .string(physicalPage)
    }

    if let cssSelector,
       !cssSelector.isEmpty {
      res["cssSelector"] = .string(cssSelector)
    }

    if let currentPage, currentPage > 0 {
      res["currentPage"] = .integer(currentPage)
    }

    if let totalPages, totalPages > 0 {
      res["totalPages"] = .integer(totalPages)
    }

    return res
  }

  static func fromJson(_ jsonString: String) throws -> PageInformation {
    let data = Data(jsonString.utf8)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    return fromJson(object)
  }

  static func fromJson(_ json: [String: Any]) -> PageInformation {
    let tocId = json["tocId"] as? String
    let physicalPage = json["physicalPage"] as? String
    let cssSelector = json["cssSelector"] as? String
    let currentPage = json["currentPage"] as? Int
    let totalPages = json["totalPages"] as? Int

    return PageInformation(
      tocId: tocId,
      physicalPage: physicalPage,
      cssSelector: cssSelector,
      currentPage: currentPage,
      totalPages: totalPages
    )
  }
}
