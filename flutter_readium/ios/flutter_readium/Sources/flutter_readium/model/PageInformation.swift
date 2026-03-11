import Foundation

final class PageInformation {
  
  let tocId: String?
  let physicalPage: String?
  let cssSelector: String?
  
  init(tocId: String?, physicalPage: String?, cssSelector: String?) {
    self.tocId = tocId
    self.physicalPage = physicalPage
    self.cssSelector = cssSelector
  }
  
  var otherLocations: [String: Any] {
    var res: [String: Any] = [:]
    
    if let tocId,
       !tocId.isEmpty {
      res["tocId"] = tocId
    }
    
    if let physicalPage,
       !physicalPage.isEmpty {
      res["physicalPage"] = physicalPage
    }
    
    if let cssSelector,
       !cssSelector.isEmpty {
      res["cssSelector"] = cssSelector
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
    
    return PageInformation(
      tocId: tocId,
      physicalPage: physicalPage,
      cssSelector: cssSelector
    )
  }
}
