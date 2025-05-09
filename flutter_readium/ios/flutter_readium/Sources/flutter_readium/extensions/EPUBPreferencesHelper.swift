import ReadiumNavigator

// TODO: Refactor into a EPUBPreferences extension

public class EPUBPreferencesHelper {
  static let TAG = "EPUBPreferencesHelper"

  public static func mapToEPUBPreferences(_ dictionary: Dictionary<String, String>) -> EPUBPreferences {
    var preferences = EPUBPreferences()

    for (key, value) in dictionary {
      switch key {
      case "backgroundColor":
        preferences.backgroundColor = Color(hex: value)
      case "columnCount":
        if let columnCountValue = ColumnCount(rawValue: value) {
          preferences.columnCount = columnCountValue
        }
      case "fontFamily":
        preferences.fontFamily = FontFamily(rawValue: value)

      case "fontSize":
        if let fontSizeValue = Double(value) {
          preferences.fontSize = fontSizeValue
        }
      case "fontWeight":
        if let fontWeightValue = Double(value) {
          preferences.fontWeight = fontWeightValue
        }
      case "hyphens":
        preferences.hyphens = (value == "true")
      case "imageFilter":
        if let imageFilterValue = ImageFilter(rawValue: value) {
          preferences.imageFilter = imageFilterValue
        }
      case "letterSpacing":
        if let letterSpacingValue = Double(value) {
          preferences.letterSpacing = letterSpacingValue
        }
      case "ligatures":
        preferences.ligatures = (value == "true")
      case "lineHeight":
        if let lineHeightValue = Double(value) {
          preferences.lineHeight = lineHeightValue
        }
      case "pageMargins":
        if let pageMarginsValue = Double(value) {
          preferences.pageMargins = pageMarginsValue
        }
      case "paragraphIndent":
        if let paragraphIndentValue = Double(value) {
          preferences.paragraphIndent = paragraphIndentValue
        }
      case "paragraphSpacing":
        if let paragraphSpacingValue = Double(value) {
          preferences.paragraphSpacing = paragraphSpacingValue
        }
      case "verticalScroll":
        preferences.scroll = (value == "true")
      case "spread":
        if let spreadValue = Spread(rawValue: value) {
          preferences.spread = spreadValue
        }
      case "textAlign":
        if let textAlignValue = TextAlignment(rawValue: value) {
          preferences.textAlign = textAlignValue
        }
      case "textColor":
        preferences.textColor = Color(hex: value)
      case "textNormalization":
        preferences.textNormalization = (value == "true")
      case "theme":
        if let themeValue = Theme(rawValue: value) {
          preferences.theme = themeValue
        }
      case "typeScale":
        if let typeScaleValue = Double(value) {
          preferences.typeScale = typeScaleValue
        }
      case "verticalText":
        preferences.verticalText = (value == "true")
      case "wordSpacing":
        if let wordSpacingValue = Double(value) {
          preferences.wordSpacing = wordSpacingValue
        }
      case "--USER__highlightBackgroundColor", "--USER__highlightForegroundColor":
        // Ignore custom properties
        break
      default:
        print(TAG, "ERROR: Unsupported Property: \(key): \(value)")
      }
    }

    return preferences
  }
}
