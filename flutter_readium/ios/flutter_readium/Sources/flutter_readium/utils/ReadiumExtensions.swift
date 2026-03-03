import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import ReadiumInternal

extension Locator {
  var timeOffset: TimeInterval? {
    // Get time offset
    let fragment: String? = locations.fragments.first(where: { $0.hasPrefix("t=") })
    let offsetStr = fragment?.removingPrefix("t=")
    return offsetStr != nil ? TimeInterval(offsetStr!) : nil
  }

  var textId: String? {
    let cssFragment = locations.fragments.first(where: { $0.hasPrefix("#") }) ?? locations.cssSelector
    return cssFragment?.removingPrefix("#")
  }
}

extension Publication {
  var containsMediaOverlays: Bool {
    self.readingOrder.contains(where: { $0.alternates.contains(where: { $0.mediaType?.matches(MediaType("application/vnd.syncnarr+json")) == true })})
  }
  
  func getFlattenedToC() async -> [Link] {
    switch await self.tableOfContents() {
    case .success(let toc):
      return toc.flatMap{ $0.flatten() }
    case .failure(let err):
      debugPrint("failed to retrieve ToC: \(err)")
      return []
    }
  }
  
  func searchInContentForQuery(_ query: String) async -> [LocatorCollection] {
    guard let searchService: SearchService = findService(SearchService.self) else {
      debugPrint("No SearchService available")
      return []
    }
    var collections: [LocatorCollection] = []
    switch await searchService.search(query: query, options: .init()) {
    case .failure(let err):
      switch err {
      case .badQuery(let queryErr):
        debugPrint("Search failed, bad query: \(queryErr)")
      case .reading(let readErr):
        debugPrint("Search failed, reading error: \(readErr)")
      case .publicationNotSearchable:
        debugPrint("Search failed, publication is not searchable")
      }
    case .success(let iterator):
      _ = await iterator.forEach { collection in
        collections.append(collection)
      }
    }
    return collections
  }
  
  /**
   * Helper for getting all cssSelectors for a HTML document in the Publication.
   */
  func findAllCssSelectors(hrefRelativePath: String) async -> [String] {
    if (!self.conforms(to: Publication.Profile.epub)) {
      debugPrint("This only works for EPUBs")
      return []
    }
    guard let contentService: ContentService = findService(ContentService.self) else {
      debugPrint("No ContentService available")
      return []
    }
    let cleanHref = hrefRelativePath,
        startLocator = Locator(href: RelativeURL(string: cleanHref)!, mediaType: MediaType.xhtml)
        
    let content = contentService.content(from: startLocator)?.iterator()
    if (content == nil) {
      debugPrint("No content iterator obtained from ContentService")
      return []
    }
    
    var ids = [] as [String]

    while let element: ContentElement? = try? await content?.next() {
      if (element == nil) {
        continue
      }
      if (element?.locator.href.path != cleanHref) {
        break
      }
      
      if let cssSelector = element?.locator.locations.cssSelector.takeIf({ $0.hasPrefix("#") }) {
        ids.append(cssSelector)
      }
    }
    return ids
  }
  
  /**
   * Find the cssSelector for a locator. If it already have one return it, otherwise we need to look it up.
   */
  func findCssSelectorForLocator(locator: Locator) async -> String? {
    if locator.locations.cssSelector?.hasPrefix("#") == true {
      return locator.locations.cssSelector
    }
    
    guard let contentService: ContentService = findService(ContentService.self) else {
      debugPrint("No ContentService available")
      return nil
    }
    
    let cleanPath = locator.href.path
    let content = contentService.content(from: locator)?.iterator()
    if (content == nil) {
      debugPrint("No content iterator obtained from ContentService")
      return nil
    }
    let locatorProgression = locator.locations.progression ?? 0.0
    var lastPassedCssSelector: String? = nil
    
    while let element: ContentElement? = try? await content?.next() {
      debugPrint("findCssSelector: \(element?.locator.href.path ?? ""), \(element?.locator.locations.progression ?? 0.0), \(element?.locator.locations.cssSelector ?? "")")
      if (element == nil || element?.locator.href.path != cleanPath) {
        // End of content iterator or went past current HTML resource.
        break
      }
      let progression = element?.locator.locations.progression ?? 0.0
      if (progression > locatorProgression && lastPassedCssSelector != nil) {
        // We're past Locator's progression and previously found a cssSelector, break out and return it.
        break;
      }
      // Save the passed CSS selector.
      if let cssSelector = element?.locator.locations.cssSelector.takeIf({ $0.hasPrefix("#") }) {
        lastPassedCssSelector = cssSelector.split(separator: " ").first?.lowercased()
      }
    }
    return lastPassedCssSelector
  }
}

extension MediaPlaybackState {
  var asTimebasedState: TimebasedState {
    switch self {
    case .paused: return .paused
    case .playing: return .playing
    case .loading: return .loading
    }
  }
}

extension PublicationSpeechSynthesizer.State {
  var asTimebasedState: TimebasedState {
    switch self {
    case .paused: return .paused
    case .playing: return .playing
    case .stopped: return .ended
    }
  }
}

extension Link {
  init(fromJsonString jsonString: String) throws {
    do {
      let jsonObj = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!)
      try self.init(json: jsonObj)
    } catch {
      print("Invalid Link object: \(error)")
      throw JSONError.parsing(Self.self)
    }
  }
  
  func flatten() -> [Link] {
    return [self] + children.flatMap{ $0.flatten() }
  }
}

extension Decoration {
  init(fromJson jsonString: String) throws {
    let jsonMap: Dictionary<String, String>?
    do {
      jsonMap = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? Dictionary<String, String>
    } catch {
      print("Invalid Decoration object: \(error)")
      throw JSONError.parsing(Self.self)
    }
    try self.init(fromMap: jsonMap)
  }

  init(fromMap jsonMap: Dictionary<String, String>?) throws {
    guard let jsonObject = jsonMap,
          let idString = jsonObject["id"],
          let locator = try Locator.init(jsonString: jsonObject["locator"]!),
          let styleStr = jsonObject["style"],
          let tintHexStr = jsonObject["tint"],
          let tintColor = Color(hex: tintHexStr),
          let style = try? Decoration.Style.init(withStyle: styleStr, tintColor: tintColor) else {
      print("Decoration parse error: `id`, `locator`, `style` and `tint` required")
      throw JSONError.parsing(Self.self)
    }
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

  init(fromJson jsonString: String) throws {
    let jsonMap: Dictionary<String, String>?
    do {
      jsonMap = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? Dictionary<String, String>
    } catch {
      print("Invalid Decoration.Style json map: \(error)")
      throw JSONError.parsing(Self.self)
    }
    try self.init(fromMap: jsonMap)
  }

  init(fromMap jsonMap: Dictionary<String, String>?) throws {
    guard let map = jsonMap,
          let styleStr = map["style"],
          let tintHexStr = map["tint"],
          let tintColor = Color(hex: tintHexStr)
    else {
      print("Decoration parse error: `style` and `tint` required")
      throw JSONError.parsing(Self.self)
    }
    try self.init(withStyle: styleStr, tintColor: tintColor)
  }
}

extension TTSVoice.Quality {
  // Returns string matching TTSVoiceQuality enum on Flutter side.
  // Biggest difference is that medium = normal.
  public var toFlutterString: String {
    switch self {
    case .low, .lower:
      return "low"
    case .medium:
      return "normal"
    case .high, .higher:
      return "high"
    @unknown default:
      return "normal"
    }
  }
}

extension TTSVoice {
  public var json: JSONDictionary.Wrapped {
    makeJSON([
      "identifier": identifier,
      "name": name,
      "gender": String.init(describing: gender),
      "quality": quality?.toFlutterString ?? "normal",
      "language": language.description,
    ])
  }
  public var jsonString: String? {
    serializeJSONString(json)
  }
}

extension EPUBPreferences {
  init(fromMap jsonMap: Dictionary<String, String>) {
    self.init()

    for (key, value) in jsonMap {
      switch key {
      case "backgroundColor":
        backgroundColor = Color(hex: value)
      case "columnCount":
        if let columnCountValue = ColumnCount(rawValue: value) {
          columnCount = columnCountValue
        }
      case "fontFamily":
        fontFamily = FontFamily(rawValue: value)
      case "fontSize":
        if let fontSizeValue = Double(value) {
          fontSize = fontSizeValue
        }
      case "fontWeight":
        if let fontWeightValue = Double(value) {
          fontWeight = fontWeightValue
        }
      case "hyphens":
        hyphens = (value == "true")
      case "imageFilter":
        if let imageFilterValue = ImageFilter(rawValue: value) {
          imageFilter = imageFilterValue
        }
      case "letterSpacing":
        if let letterSpacingValue = Double(value) {
          letterSpacing = letterSpacingValue
        }
      case "ligatures":
        ligatures = (value == "true")
      case "lineHeight":
        if let lineHeightValue = Double(value) {
          lineHeight = lineHeightValue
        }
      case "pageMargins":
        if let pageMarginsValue = Double(value) {
          pageMargins = pageMarginsValue
        }
      case "paragraphIndent":
        if let paragraphIndentValue = Double(value) {
          paragraphIndent = paragraphIndentValue
        }
      case "paragraphSpacing":
        if let paragraphSpacingValue = Double(value) {
          paragraphSpacing = paragraphSpacingValue
        }
      case "verticalScroll":
        scroll = (value == "true")
      case "spread":
        if let spreadValue = Spread(rawValue: value) {
          spread = spreadValue
        }
      case "textAlign":
        if let textAlignValue = TextAlignment(rawValue: value) {
          textAlign = textAlignValue
        }
      case "textColor":
        textColor = Color(hex: value)
      case "textNormalization":
        textNormalization = (value == "true")
      case "theme":
        if let themeValue = Theme(rawValue: value) {
          theme = themeValue
        }
      case "typeScale":
        if let typeScaleValue = Double(value) {
          typeScale = typeScaleValue
        }
      case "verticalText":
        verticalText = (value == "true")
      case "wordSpacing":
        if let wordSpacingValue = Double(value) {
          wordSpacing = wordSpacingValue
        }
      default:
        print("EPUBPreferences", "WARN: Cannot map property: \(key): \(value)")
      }
    }
  }
}

// Map our extended AudioPreferences to Readium version.
extension AudioPreferences {
  public init(fromFlutterPrefs prefs: FlutterAudioPreferences) {
    self.init(
      volume: prefs.volume,
      speed: prefs.speed,
    )
  }
}
