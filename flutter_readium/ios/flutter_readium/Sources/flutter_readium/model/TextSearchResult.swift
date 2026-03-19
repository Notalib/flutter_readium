import ReadiumShared

struct TextSearchResult {
  let locator: Locator
  let chapterTitle: String?
  let pageNumbers: [String]?

  public init(locator: Locator, chapterTitle: String? = nil, pageNumbers: [String]? = nil) {
    self.locator = locator
    self.chapterTitle = chapterTitle
    self.pageNumbers = pageNumbers
  }
  
  func toJson() -> [String: Any?] {
    let map: [String: Any?] = [
      "locator": locator.jsonString,
      "chapterTitle": chapterTitle,
      "pageNumbers": pageNumbers?.joined(separator: ","),
    ]
    
    return map
  }
  
  func toJsonString(pretty: Bool = false) throws -> String? {
    let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
    let data = try JSONSerialization.data(withJSONObject: toJson(), options: options)
    return String(data: data, encoding: .utf8)
  }
}
