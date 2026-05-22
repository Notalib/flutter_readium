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

  var containsGuidedNavigationMediaOverlays: Bool {
    let mt = MediaType("application/guided-navigation+json")!
    return !links.filterByMediaType(mt).isEmpty ||
      readingOrder.contains(where: { !$0.alternates.filterByMediaType(mt).isEmpty })
  }

  /// Whether the publication has any audio-text synchronization data,
  /// either as syncnarr media overlays or as guided navigation.
  var containsSyncNarration: Bool {
    containsMediaOverlays || containsGuidedNavigationMediaOverlays
  }

  /// Enriches a list of overlays with title and tocHref from the publication's table of contents.
  /// Uses a sliding-window approach: items that don't match a ToC entry directly inherit the last
  /// matched entry when they share the same text file.
  private func enrichOverlaysWithToc(_ overlays: [FlutterMediaOverlay]) -> [FlutterMediaOverlay] {
    let toc = getFlattenedToC()
    var lastTocMatch: Link? = nil
    return overlays.map { overlay in
      let items = overlay.items.map { item -> FlutterMediaOverlayItem in
        if let match = toc.first(where: { $0.href == item.text }) {
          lastTocMatch = match
          return item.copyWith(tocTitle: match.title, tocHref: match.href)
        } else if let last = lastTocMatch, last.href.substringBeforeLast("#") == item.textFile {
          return item.copyWith(tocTitle: last.title, tocHref: last.href)
        }
        return item
      }
      return FlutterMediaOverlay(items: items, readingOrderDuration: overlay.readingOrderDuration ?? overlay.totalDuration)
    }
  }
  
  func getSyncNarrationMediaOverlays() async -> [FlutterMediaOverlay]? {
    if (containsGuidedNavigationMediaOverlays) {
      return await getGuidedNavigationMediaOverlays()
    }
    else if (containsSyncNarration) {
      return await getMediaOverlays()
    }
    return nil
  }

  func getMediaOverlays() async -> [FlutterMediaOverlay]? {
    guard containsMediaOverlays else { return nil }

    let narrationLinks = self.narrationLinks

    let narrationJson = await narrationLinks.asyncCompactMap { try? await self.get($0)?.readAsJSONObject().get() }
    let rawOverlays = narrationJson.enumerated().compactMap({ idx, json in
      let roDuration = readingOrder.getOrNil(idx)?.duration
      return FlutterMediaOverlay.fromJson(json, atPosition: idx, atTocHref: nil, readingOrderDuration: roDuration)
    })

    // Assert that we did not lose any MediaOverlays during JSON deserialization.
    assert(rawOverlays.count == narrationLinks.count)

    return enrichOverlaysWithToc(rawOverlays)
  }

  func getGuidedNavigationMediaOverlays() async -> [FlutterMediaOverlay]? {
    guard containsGuidedNavigationMediaOverlays else { return nil }

    let guidedNavMediaType = MediaType("application/guided-navigation+json")!

    // Strategy 1: single guided navigation document in publication links (preferred).
    if let singleDocLink = links.filterByMediaType(guidedNavMediaType).first {
      guard
        let json = try? await get(singleDocLink)?.readAsJSONObject().get(),
        let document = GuidedNavigationDocument.fromJson(json)
      else { return nil }

      let rawOverlays = document.toMediaOverlays()
      let positionedOverlays = rawOverlays.compactMap { overlay -> FlutterMediaOverlay? in
        guard let textFile = overlay.textFile else { return nil }
        let roEntry = readingOrder.enumerated().first {
          $1.href.split(separator: "#", maxSplits: 1).first.map(String.init) == textFile
        }
        let position = (roEntry?.offset ?? -1) + 1
        let duration = roEntry?.element.duration
        let items = overlay.items.map { item -> FlutterMediaOverlayItem in
          FlutterMediaOverlayItem(
            audio: item.audio, text: item.text, position: position, readingOrderDuration: duration)
        }
        return FlutterMediaOverlay(items: items, readingOrderDuration: duration)
      }
      return enrichOverlaysWithToc(positionedOverlays)
    }

    // Strategy 2: per-item alternates in reading order.
    var hasAny = false
    var allOverlays: [FlutterMediaOverlay] = []
    for (idx, roLink) in readingOrder.enumerated() {
      guard let gnLink = roLink.alternates.filterByMediaType(guidedNavMediaType).first else { continue }
      hasAny = true
      guard
        let json = try? await get(gnLink)?.readAsJSONObject().get(),
        let document = GuidedNavigationDocument.fromJson(json)
      else { continue }
      allOverlays += document.toMediaOverlays(atPosition: idx + 1, readingOrderDuration: roLink.duration)
    }
    guard hasAny else { return nil }
    return enrichOverlaysWithToc(allOverlays)
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
