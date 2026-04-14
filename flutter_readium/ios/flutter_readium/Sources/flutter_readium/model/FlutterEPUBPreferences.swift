import ReadiumNavigator

public struct FlutterEPUBPreferences {
  
  /// Base preferences for Readium Navigator.
  public var readium: EPUBPreferences
  /// B&W modification for comics.
  public var blackAndWhite: Bool?
  /// Flag to switch off automatic sync from audio position to visual reader.
  public var disableSync: Bool?

  init(fromMap jsonMap: Dictionary<String, Any>) {
    readium = EPUBPreferences.init(fromMap: jsonMap)

    for (key, value) in jsonMap {
      switch key {
      case "blackAndWhiteComicMode":
        blackAndWhite = value as? Bool
      case "disableSynchronization":
        disableSync = value as? Bool
      default:
        Log.readium.warn("FlutterEPUBPreferences unable to map JSON property: \(key)=\(value)")
      }
    }
  }
}
