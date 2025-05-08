import Foundation
import ReadiumNavigator
import ReadiumShared
import ReadiumInternal

extension Decoration {
  init(fromJson jsonString: String) throws {
    let json: Any?
    do {
        json = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!)
    } catch {
        print("Invalid Decoration object: \(error)")
        throw JSONError.parsing(Self.self)
    }
    guard let jsonObject = json as? Dictionary<String, String>,
          let idString = jsonObject["id"],
          let locator = try Locator.init(jsonString: jsonObject["locator"]!),
          let styleStr = jsonObject["style"],
          let tintHexStr = jsonObject["tint"],
          let tintColor = Color(hex: tintHexStr)
    else {
        print("Decoration parse error: `id`, `locator`, `style` and `tint` required")
        throw JSONError.parsing(Self.self)
    }
    let style = try Decoration.Style.init(withStyle: styleStr, tintColor: tintColor)

    self.init(
        id: idString as Id,
        locator: locator,
        style: style,
    )
  }
}

extension Decoration.Style {
  init(withStyle style: String, tintColor: Color) throws {
    let styleId = Decoration.Style.Id(rawValue: style)
    self.init(id: styleId, config: HighlightConfig(tint: tintColor.uiColor))
  }
}

extension TTSVoice {
  public var json: JSONDictionary.Wrapped {
      makeJSON([
        "identifier": identifier,
        "name": name,
        "gender": String.init(describing: gender),
        "quality": quality != nil ? String.init(describing: quality!) : nil,
        "language": language.description,
      ])
  }
  public var jsonString: String? {
      serializeJSONString(json)
  }
}
