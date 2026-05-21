import ReadiumNavigator
import ReadiumShared

/// Maps the Dart PDFPreferences JSON map to ReadiumNavigator's
/// PDFNavigatorViewController.Preferences for runtime updates.
struct FlutterPDFPreferences {
  var readium: PDFNavigatorViewController.Preferences = .init()

  init() {}

  init(fromMap map: [String: Any]) {
    var prefs = PDFNavigatorViewController.Preferences()
    // Unified PDFLayout enum from Dart, translated into PDFKit's `scroll` +
    // `scrollAxis` pair. `paginated` uses scroll=false (snap-to-page);
    // the two `scroll*` cases use scroll=true with the matching axis.
    if let layoutString = map["layout"] as? String {
      switch layoutString {
      case "paginated":
        prefs.scroll = false
      case "scrollVertical":
        prefs.scroll = true
        prefs.scrollAxis = .vertical
      case "scrollHorizontal":
        prefs.scroll = true
        prefs.scrollAxis = .horizontal
      default:
        break
      }
    }
    if let rpString = map["readingProgression"] as? String,
       let rp = ReadiumNavigator.ReadingProgression(rawValue: rpString) {
      prefs.readingProgression = rp
    }
    readium = prefs
  }
}
