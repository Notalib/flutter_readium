import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import ReadiumInternal

extension Locator {
  var timeOffset: TimeInterval? {
    // Get time offset
    let fragment: String? = locations.fragments.first(where: { $0.hasPrefix("t=") })
    if let offsetStr = fragment?.removingPrefix("t=").removingPrefix("npt:") {
      return TimeInterval(offsetStr)
    } else {
      return nil
    }
  }

  var textId: String? {
    let cssFragment = locations.fragments.first(where: { $0.hasPrefix("#") }) ?? locations.cssSelector
    return cssFragment?.removingPrefix("#")
  }
  
  /// Prepares the Locator data to be sent over the Flutter bridge to clients.
  /// Some fields are better off rounded before being passed over the bridge.
  func toClientFriendlyLocator() -> Locator {
    let offset = timeOffset
    var totalProgress = locations.totalProgression
    
    if totalProgress != nil {
      totalProgress = Double(String(format: "%.4f", totalProgress!))
    }
    
    return copy(locations: { locs in
      locs.fragments = offset != nil ? [String(format: "t=%.2f", offset!)] : []
      locs.totalProgression = totalProgress
    })
  }
  
  /// Gets a Locator copy overriding fragments with a Readium compatible time fragment.
  func copyWithOffset(_ offset: Double) -> Locator {
    return copy(locations: { locs in locs.fragments = ["t=\(offset)"] })
  }
  
  func copyWithProgressionLocations(progression: Double) -> Locator {
    return copy(locations: { locs in
      locs.fragments = []
      locs.otherLocations = [:]
      locs.progression = progression
    })
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

    let toc: [Link] = getFlattenedToC()
    var lastTocMatch: Link? = nil

    let narrationJson = await narrationLinks.asyncCompactMap { try? await self.get($0)?.readAsJSONObject().get() }
    let mediaOverlays = narrationJson.enumerated().compactMap({ idx, json in
      /// Fetch the expected total duration of this MediaOverlay from the reading-order.
      let roDuration = readingOrder.getOrNil(idx)?.duration
      return FlutterMediaOverlay.fromJson(json, atPosition: idx, atTocHref: nil, readingOrderDuration: roDuration)
    }).map({ (overlay: FlutterMediaOverlay) in
      /// For each item in the top-level MediaOverlay enrich it with href and title from the ToC where matchable.
      let items = overlay.items.map { item in
        // Find best matching title from ToC (via text URL)
        if let match = toc.first(where: { tocItem in tocItem.href == item.text }) {
          lastTocMatch = match
          return item.copyWith(tocTitle: match.title, tocHref: match.href)
        } else if (lastTocMatch != nil && lastTocMatch?.href.substringBeforeLast("#") == item.textFile) {
          return item.copyWith(tocTitle: lastTocMatch?.title, tocHref: lastTocMatch?.href)
        }
        return item
      }
      /// Re-create the top-level MediaOverlay item with its enriched items and reading-order duration
      /// If no duration in the reading-order, it calculates a total duration for all its items.
      return FlutterMediaOverlay(items: items, readingOrderDuration: overlay.readingOrderDuration ?? overlay.totalDuration)
    })

    // Assert that we did not lose any MediaOverlays during JSON deserialization.
    assert(mediaOverlays.count == narrationLinks.count)

    return mediaOverlays
  }

  func searchInContentForQuery(_ query: String) async -> Result<[LocatorCollection], Error> {
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
  init(fromMap jsonMap: Dictionary<String, Any>) {
    self.init()

    for (key, value) in jsonMap {
      switch key {
      case "backgroundColor":
        if let colorStr = value as? String {
          backgroundColor = Color(hex: colorStr)
        }
      case "columnCount":
        if let columnCountStr = value as? String {
          columnCount = ColumnCount(rawValue: columnCountStr)
        }
      case "fit":
        if let fitStr = value as? String {
          fit = Fit(rawValue: fitStr)
        }
      case "fontFamily":
        if let fontFamilyStr = value as? String {
          fontFamily = FontFamily(rawValue: fontFamilyStr)
        }
      case "fontSize":
        if let fontSizeValue = value as? Double {
          fontSize = Double(fontSizeValue / 100.0)
        }
      case "fontWeight":
        if let fontWeightValue = value as? Double {
          fontWeight = fontWeightValue
        }
      case "hyphens":
        hyphens = value as? Bool
      case "imageFilter":
        if let imageFilterStr = value as? String {
          imageFilter = ImageFilter(rawValue: imageFilterStr)
        }
      case "language":
        if let languageCode = value as? Language.Code {
          language = Language(code: languageCode)
        }
      case "letterSpacing":
        if let letterSpacingValue = value as? Double {
          letterSpacing = letterSpacingValue
        }
      case "ligatures":
        ligatures = value as? Bool
      case "lineHeight":
        lineHeight = value as? Double
      case "offsetFirstPage":
        offsetFirstPage = value as? Bool
      case "pageMargins":
        pageMargins = value as? Double
      case "paragraphIndent":
        paragraphIndent = value as? Double
      case "paragraphSpacing":
        paragraphSpacing = value as? Double
      case "publisherStyles":
        publisherStyles = value as? Bool
      case "readingProgression":
        if let readingProgressionStr = value as? String {
          readingProgression = ReadingProgression(rawValue: readingProgressionStr)
        }
      case "scroll":
        scroll = value as? Bool
      case "spread":
        if let spreadValueStr = value as? String {
          spread = Spread(rawValue: spreadValueStr)
        }
      case "textAlign":
        if let textAlignStr = value as? String {
          textAlign = TextAlignment(rawValue: textAlignStr)
        }
      case "textColor":
        if let colorStr = value as? String, let color = Color(hex: colorStr) {
          textColor = color
        }
      case "textNormalization":
        textNormalization = value as? Bool
      case "theme":
        if let themeValueStr = value as? String {
          theme = Theme(rawValue: themeValueStr)
        }
      case "typeScale":
          typeScale = value as? Double
      case "verticalText":
        verticalText = value as? Bool
      case "wordSpacing":
        wordSpacing = value as? Double
      default:
        Log.readium.debug("EPUBPreferences unable to map JSON property: \(key)=\(value)")
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
