import ReadiumNavigator
import ReadiumShared

/// Maps the Dart PDFPreferences JSON map to ReadiumNavigator's
/// PDFNavigatorViewController.Preferences for runtime updates.
struct FlutterPDFPreferences {
  var readium: PDFNavigatorViewController.Preferences = .init()

  init() {}

  init(fromMap map: [String: Any]) {
    var prefs = PDFNavigatorViewController.Preferences()
    if let scroll = map["scroll"] as? Bool {
      prefs.scroll = scroll
    }
    if let rpString = map["readingProgression"] as? String,
       let rp = ReadingProgression(rawValue: rpString) {
      prefs.readingProgression = rp
    }
    readium = prefs
  }
}
