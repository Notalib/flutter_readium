import Foundation
import ReadiumShared

struct FlutterMediaOverlay {
  let items: [FlutterMediaOverlayItem]
  
  let readingOrderDuration: TimeInterval?
  
  var audioFile: String? {
    items.first?.audioFile
  }
  
  var textFile: String? {
    items.first?.textFile
  }
  
  var totalDuration: TimeInterval? {
    items.reduce(0) { $0 + ($1.audioDuration ?? 0.0) }
  }

  func itemInRangeOfTime(_ time: Double, inHref href: String) -> FlutterMediaOverlayItem? {
    if (href != audioFile && href != textFile) {
      return nil
    }

    return items.first(where: { $0.isAudioInRangeOfTime(time, inHref: href) })
  }
  
  func itemFromTextId(_ textId: String, inHref href: String) -> FlutterMediaOverlayItem? {
    if (textFile != href && audioFile != href) {
      return nil
    }
    
    return items.first(where: { $0.textId == textId })
  }
  
  func itemFromLocator(_ locator: Locator) -> FlutterMediaOverlayItem? {
    let href = locator.href.string
    if (textFile != href && audioFile != href) {
      return nil
    }
    
    // Audio time fragment → exact item by time range.
    let timeOffset = locator.timeOffset
    if (timeOffset != nil) {
      return itemInRangeOfTime(timeOffset!, inHref: href)
    }

    // DiViNa comic page: the page locator's only anchor is a generic "img" css selector
    // (which `textId` would otherwise pick up), not a media-overlay text id. Match the
    // page's first narrated item by href — the textref is the image itself.
    if (locator.mediaType.isBitmap) {
      return items.first(where: { $0.textFile == href })
    }

    // Reflowable text: match by DOM element id when present.
    let textId = locator.textId
    if (textId != nil) {
      return itemFromTextId(textId!, inHref: href)
    }

    // No fragment on a text document → first item of the resource.
    if (locator.locations.fragments.isEmpty && [MediaType.html, MediaType.xhtml].contains(locator.mediaType)) {
      return items.first(where: { $0.textFile == href })
    }

    return nil
  }
  
  static func fromJson(_ json: [String: Any], atPosition position: Int, atTocHref: String? = nil, readingOrderDuration: TimeInterval? = nil) -> FlutterMediaOverlay? {
    guard let topNarration = json["narration"] as? [[String: Any]] else { return nil }
    var acc: [FlutterMediaOverlayItem] = []
    
    for obj in topNarration {
      if let item = FlutterMediaOverlayItem.fromJson(obj, atPosition: position, atTocHref: atTocHref, readingOrderDuration: readingOrderDuration) {
        acc.append(item)
      }
      // recurse if nested containers also have "narration"
      if let nested = FlutterMediaOverlay.fromJson(obj, atPosition: position, atTocHref: atTocHref, readingOrderDuration: readingOrderDuration) {
        acc.append(contentsOf: nested.items)
      }
    }
    return FlutterMediaOverlay(items: acc, readingOrderDuration: readingOrderDuration)
  }
}

struct FlutterMediaOverlayItem {
  let audio: String
  let text: String
  let position: Int
  let readingOrderDuration: TimeInterval?
  
  let audioFile: String
  let audioMediaType: MediaType
  private let audioFragment: String

  let audioStart: Double?
  let audioEnd: Double?
  
  var audioDuration: Double? {
    guard let audioStart, let audioEnd else { return nil }
    return max(0, audioEnd - audioStart)
  }
  
  let textFile: String
  let textId: String
  
  let tocTitle: String?
  let tocHref: String?
  
  init(audio: String, text: String, position: Int, tocTitle: String? = nil, tocHref: String? = nil, readingOrderDuration: TimeInterval? = nil) {
    self.audio = audio
    self.text = text
    self.position = position
    self.tocTitle = tocTitle
    self.tocHref = tocHref
    self.readingOrderDuration = readingOrderDuration
    self.audioFile = audio.split(separator: "#", maxSplits: 1).first.map(String.init) ?? audio
    self.audioFragment = audio.split(separator: "#", maxSplits: 1).getOrNil(1).map(String.init) ?? ""
    self.textFile = text.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
    self.textId = text.split(separator: "#", maxSplits: 1).getOrNil(1).map(String.init) ?? ""
    self.audioMediaType = switch (audioFile.split(separator: ".").last) {
      case "opus" :
        MediaType.opus
      default:
        MediaType.mpegAudio
    }
    
    if let range = MediaTimeFragment.range(from: audioFragment) {
      self.audioStart = range.start
      self.audioEnd = range.end
    } else {
      self.audioStart = nil
      self.audioEnd = nil
    }
  }
  
  func copyWith(tocTitle: String?, tocHref: String?) -> FlutterMediaOverlayItem {
    return FlutterMediaOverlayItem(audio: audio, text: text, position: position, tocTitle: tocTitle, tocHref: tocHref, readingOrderDuration: readingOrderDuration)
  }
  
  static func == (lhs: FlutterMediaOverlayItem, rhs: FlutterMediaOverlayItem) -> Bool {
    return lhs.audio == rhs.audio && lhs.text == rhs.text && lhs.position == rhs.position
  }
  
  /// Check if this MediaOverlayItem matched href and has time-fragment range matching a given time.
  func isAudioInRangeOfTime(_ time: Double, inHref href: String) -> Bool {
    if (textFile != href && audioFile != href) {
      return false
    }
    guard let start = audioStart else { return false }
    // A reversed or non-finite end (malformed `t=start,end` fragment) would trap
    // `start...end`; treat it as open-ended from `start`, mirroring the no-end case.
    guard let end = audioEnd, end >= start else { return time >= start }
    return (start...end).contains(time)
  }
  
  // MARK: Locators
  
  /// Create a Text-based Locator representing this MediaOverlayItem
  var asTextLocator: Locator? {
    guard
      let href = URL(string: text.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "")
    else { return nil }
    
    let frag = text.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)
    var locator = Locator(
      href: href,
      mediaType: MediaType.xhtml,
      title: tocTitle,
      locations: .init(
        fragments: frag.map { [$0] } ?? [],
      )
    )
    if (frag != nil) {
      locator.locations.otherLocations["cssSelector"] = .string("#\(frag!)")
    }
    if (tocHref != nil) {
      locator.locations.otherLocations["tocHref"] = .string(tocHref!)
    }
    return locator
  }
  
  /// Create an Audio-based Locator representing this MediaOverlayItem
  var asAudioLocator: Locator? {
    guard let href = URL(string: audioFile) else { return nil }
    let start = audioStart ?? 0.0
    return Locator(
      href: href,
      mediaType: audioMediaType,
      locations: .init(fragments: [MediaTimeFragment.string(start)])
    )
  }
  
  /// Combine this MediaOverlayItem as a Text-based Locator, with an Audio-based Locator.
  /// This is generally used to report back a synchronizable Locator to Flutter client and backends.
  func toCombinedLocator(fromAudioLocator audioLocator: Locator) -> Locator? {
    guard var textLocator = self.asTextLocator else { return nil }
    // Combine the text-locator with given audio-locator's locations.
    // We keep the otherLocations("cssSelector") from text-locator.
    // We get the position from they MediaOverlay.position
    //
    // Keep the text DOM-id fragment ahead of the audio `t=…` fragment so the combined
    // locator stays self-sufficient for swift-toolkit's reflowable navigator, which
    // positions via `fragments.first` and ignores `cssSelector` (unlike kotlin/ts).
    // `Locator.timeOffset` still finds the `t=` fragment by prefix regardless of order, so
    // audio mapping is unaffected. See docs/parity/locator-field-priority.md.
    let textFragments = textLocator.locations.fragments
    textLocator.locations = Locator.Locations(
      fragments: textFragments + audioLocator.locations.fragments,
      progression: audioLocator.locations.progression,
      totalProgression: audioLocator.locations.totalProgression,
      position: self.position + 1,
      otherLocations: textLocator.locations.otherLocations,
    )
    return textLocator
  }
  
  // MARK: JSON
  static func fromJson(_ json: [String: Any], atPosition position: Int, atTocHref: String?, readingOrderDuration: TimeInterval?) -> FlutterMediaOverlayItem? {
    guard
      let audio = json["audio"] as? String, !audio.isEmpty,
      let text  = json["text"]  as? String, !text.isEmpty
    else { return nil }
    return FlutterMediaOverlayItem(audio: audio, text: text, position: position, tocHref: atTocHref, readingOrderDuration: readingOrderDuration)
  }
}
