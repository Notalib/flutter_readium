import ReadiumNavigator

let blackAndWhiteComicModeKey: String = "blackAndWhiteComicMode";
let disableSynchronizationKey: String = "disableSynchronization";
let firstElementTopMarginKey: String = "firstElementTopMargin";

let topMarginCssVariable = "--FLUTTER_READIUM-first-element-top-margin"
let blackAndWhiteComicModeCssVariable = "--FLUTTER_READIUM-black-white-comic-mode";

public struct FlutterEPUBPreferences {
  
  /// Base preferences for Readium Navigator.
  public var readium: EPUBPreferences = EPUBPreferences.init();
  /// B&W modification for comics.
  public var blackAndWhiteComicMode: Bool?
  /// Flag to switch off automatic sync from audio position to visual reader.
  public var disableSync: Bool?
  /// Top margin to the first element in the content.
  /// This is used to create space for UI elements like a toolbar without overlapping the content.
  public var firstElementTopMargin: Int?
  
  init() {
    readium = EPUBPreferences.init();
  }

  init(fromMap jsonMap: Dictionary<String, Any>) {
    var mutableMap = jsonMap
    /// Process our extension preferences and remove them from the map
    if let blackAndWhite = jsonMap[blackAndWhiteComicModeKey] as? Bool {
      self.blackAndWhiteComicMode = blackAndWhite
      mutableMap.removeValue(forKey: blackAndWhiteComicModeKey);
    }
    if let disableSync = jsonMap[disableSynchronizationKey] as? Bool {
      self.disableSync = disableSync
      mutableMap.removeValue(forKey: disableSynchronizationKey);
    }
    if let firstElementTopMargin = jsonMap[firstElementTopMarginKey] as? Int {
      self.firstElementTopMargin = firstElementTopMargin
      mutableMap.removeValue(forKey: firstElementTopMarginKey);
    }
    
    readium = EPUBPreferences.init(fromMap: mutableMap)
  }
  
  func toCustomCssVariables() -> [String: String?] {
      var map: [String: String?] = [:]

      map[topMarginCssVariable] = firstElementTopMargin.map { "\($0)px" }
      map[blackAndWhiteComicModeCssVariable] = (blackAndWhiteComicMode == true) ? "1" : nil

      return map
  }

  func toInjectableStyleSheet() -> String {
      let cssVariables = toCustomCssVariables()
          .compactMap { key, value -> String? in
              guard let value else { return nil }
              return "\(key): \(value) !important"
          }
          .joined(separator: ";")

      return """
      :root {\(cssVariables)}
      """
  }
}
