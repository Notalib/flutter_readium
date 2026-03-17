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

  var narrationLinks: [Link] {
    return self.readingOrder.compactMap {
      var link = $0.alternates.filterByMediaType(MediaType("application/vnd.syncnarr+json")!).first
      link?.title = $0.title
      return link
    }
  }

  func getMediaOverlays() async -> [FlutterMediaOverlay] {
    if (!containsMediaOverlays) {
      return []
    }

    let narrationLinks = self.narrationLinks

    let toc: [(String, Link)] = getFlattenedToC().map { ($0.href, $0) }
    var lastTocMatch: (String, Link)? = nil

    let narrationJson = await narrationLinks.asyncCompactMap { try? await self.get($0)?.readAsJSONObject().get() }
    let mediaOverlays = narrationJson.enumerated().compactMap({ idx, json in
      FlutterMediaOverlay.fromJson(json, atPosition: idx, atTocHref: nil)
    }).map({
      let items = $0.items.map { item in
        // Find best matching title from ToC (via text URL)
        if let match = toc.first(where: { tocItem in tocItem.0 == item.text }) {
          lastTocMatch = match
          return item.copyWith(tocTitle: match.1.title, tocHref: match.1.href)
        } else if (lastTocMatch?.1 != nil && lastTocMatch?.0.substringBeforeLast("#") == item.textFile) {
          return item.copyWith(tocTitle: lastTocMatch?.1.title, tocHref: lastTocMatch?.1.href)
        }
        return item
      }
      return FlutterMediaOverlay(items: items)
    })

    // Assert that we did not lose any MediaOverlays during JSON deserialization.
    assert(mediaOverlays.count == narrationLinks.count)

    return mediaOverlays
  }
  
  func searchInContentForQuery(_ query: String) async -> Result<[LocatorCollection]> {
    guard let searchService: SearchService = findService(SearchService.self) else {
      Log.readium.warn("No SearchService available")
      return Result.failure(SearchError.publicationNotSearchable)
    }
    var collections: [LocatorCollection] = []
    switch await searchService.search(query: query, options: .init()) {
    case .failure(let err):
      Log.readium.error("Search in publication content failed: \(err)")
      return Result.failure(err)
    case .success(let iterator):
      _ = await iterator.forEach { collection in
        collections.append(collection)
      }
    }
    return .success(collections)
  }

  /**
   * Helper for getting all cssSelectors for a HTML document in the Publication.
   */
  func findAllCssSelectors(hrefRelativePath: String) async -> [String] {
    if (!self.conforms(to: Publication.Profile.epub)) {
      Log.readium.warn("findAllCssSelectors only works for EPUBs")
      return []
    }
    guard let contentService: ContentService = findService(ContentService.self) else {
      Log.readium.warn("No ContentService available")
      return []
    }
    let cleanHref = hrefRelativePath,
        startLocator = Locator(href: RelativeURL(string: cleanHref)!, mediaType: MediaType.xhtml)

    guard let content = contentService.content(from: startLocator)?.iterator() else {
      Log.readium.warn("No content iterator obtained from ContentService")
      return []
    }

    var ids = [] as [String]

    do {
      while let element = try await content.next() {
        if (element.locator.href.path != cleanHref) {
          break
        }

        if let cssSelector = element.locator.locations.cssSelector {
          ids.append(cssSelector)
          Log.readium.debug("findAllCssSelectors: \(element.locator.href.path),id: \(cssSelector)")
        }
      }
    } catch (let err) {
      Log.readium.warn("ContentService failed to fetch next element: \(err)")
    }
    return ids
  }

  /// Get a flattened Table of Contents from the manifest.
  /// This does not support LCP PDFs, as that would require using the TableOfContentsService.
  func getFlattenedToC() -> [Link] {
    return self.manifest.tableOfContents.flattened()
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
      Log.readium.error("Invalid Link object: \(error)")
      throw JSONError.parsing(Self.self)
    }
  }

  var fragment: String? {
    return URL(string: href)?.fragment
  }

  /// Returns only the path part of the Link href.
  var hrefPath: String? {
    return URL(string: href)?.path
  }

  /// Recursively flattens the Link and its children.
  func flattened() -> [Link] {
    return [self] + children.flatMap{ $0.flattened() }
  }

  /// Gets the time-fragment if part of the Link.
  var timeFragment: String? {
    if let url = URL(string: self.href),
       let timeFragment = url.fragment?.split(separator: "&").first(where: { $0.hasPrefix("t=") }),
       let timeComponent = timeFragment.split(separator: "=").last {
      return String(timeComponent)
    } else {
      return nil
    }
  }

  /// Gets the Begin part of a time-fragment as Double in in the Link.
  var timeFragmentBegin: Double? {
    if let timeComponent = timeFragment,
       let timeBegin = timeComponent.split(separator: ",").first {
      return Double(timeBegin)
    } else {
      return nil
    }
  }
}

extension Array where Element == Link {
  func flattened() -> [Link] {
    flatMap { $0.flattened() }
  }
}

extension Decoration {
  init(fromJson jsonString: String) throws {
    let jsonMap: Dictionary<String, String>?
    do {
      jsonMap = try JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? Dictionary<String, String>
    } catch {
      Log.readium.error("Invalid Decoration object: \(error)")
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
      Log.readium.error("Decoration parse error: `id`, `locator`, `style` and `tint` required")
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
      Log.readium.error("Invalid Decoration.Style json map: \(error)")
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
      Log.readium.error("Decoration parse error: `style` and `tint` required")
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
        Log.readium.warn("EPUBPreferences unable to map JSON property: \(key)=\(value)")
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
