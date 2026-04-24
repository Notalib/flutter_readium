import ReadiumNavigator

let blackAndWhiteComicModeKey: String = "blackAndWhiteComicMode";
let disableSynchronizationKey: String = "disableSynchronization";
let firstElementTopMarginKey: String = "firstElementTopMargin";

public struct FlutterEPUBPreferences {
  
  /// Base preferences for Readium Navigator.
  public var readium: EPUBPreferences = EPUBPreferences.init();
  /// B&W modification for comics.
  public var blackAndWhite: Bool?
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
      self.blackAndWhite = blackAndWhite
      mutableMap.removeValue(forKey: disableSynchronizationKey);
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
}
