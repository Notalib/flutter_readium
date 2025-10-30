import ReadiumShared

struct FlutterMediaOverlay {
  let items: [FlutterMediaOverlayItem]
  
  var audioFile: String? {
    items.first?.audioFile
  }
  
  var textFile: String? {
    items.first?.textFile
  }
  
  var duration: Double? {
    items.last?.audioEnd ?? 0.0
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
    
    // Get time offset
    let timeOffset = locator.timeOffset
    if (timeOffset != nil) {
      return itemInRangeOfTime(timeOffset!, inHref: href)
    }
    
    let textId = locator.textId
    if (textId != nil) {
      return itemFromTextId(textId!, inHref: href)
    }
    
    if (locator.locations.fragments.isEmpty && [MediaType.html, MediaType.xhtml].contains(locator.mediaType)) {
      // No fragments found, find first item matching just the href.
      return items.first(where: { $0.textFile == href })
    }
    
    return nil
  }
  
  static func fromJson(_ json: [String: Any], atPosition position: Int) -> FlutterMediaOverlay? {
    guard let topNarration = json["narration"] as? [[String: Any]] else { return nil }
    var acc: [FlutterMediaOverlayItem] = []
    
    for obj in topNarration {
      if let item = FlutterMediaOverlayItem.fromJson(obj, atPosition: position) {
        acc.append(item)
      }
      // recurse if nested containers also have "narration"
      if let nested = FlutterMediaOverlay.fromJson(obj, atPosition: position) {
        acc.append(contentsOf: nested.items)
      }
    }
    return FlutterMediaOverlay(items: acc)
  }
}

struct FlutterMediaOverlayItem {
  let audio: String
  let text: String
  let position: Int
  
  let audioFile: String
  private let audioFragment: String
  private let audioTime: String?
  
  let audioStart: Double?
  let audioEnd: Double?
  
  var audioDuration: Double? {
    guard let audioStart, let audioEnd else { return nil }
    return max(0, audioEnd - audioStart)
  }
  
  let textFile: String
  let textId: String
  
  init(audio: String, text: String, position: Int) {
    self.audio = audio
    self.text = text
    self.position = position
    self.audioFile = audio.split(separator: "#", maxSplits: 1).first.map(String.init) ?? audio
    self.audioFragment = audio.split(separator: "#", maxSplits: 1).last.map(String.init) ?? ""
    self.audioTime = audioFragment.hasPrefix("t=") ? String(audioFragment.dropFirst(2)) : nil
    self.textFile = text.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
    self.textId = text.split(separator: "#", maxSplits: 1).last.map(String.init) ?? ""
    
    if let t = self.audioTime {
      let parts = t.split(separator: ",", maxSplits: 1).map(String.init)
      self.audioStart = Double(parts.first ?? "")
      self.audioEnd = parts.count > 1 ? Double(parts[1]) : nil
    } else {
      self.audioStart = nil
      self.audioEnd = nil
    }
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
    guard let end = audioEnd else { return time >= start }
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
      locations: .init(
        fragments: frag.map { ["#\($0)"] } ?? [],
      )
    )
    if (frag != nil) {
      locator.locations.otherLocations = ["cssSelector": "#\(frag!)"]
    }
    return locator
  }
  
  /// Create an Audio-based Locator representing this MediaOverlayItem
  var asAudioLocator: Locator? {
    guard let href = URL(string: audioFile) else { return nil }
    let start = audioStart ?? 0.0
    return Locator(
      href: href,
      mediaType: MediaType.mpegAudio,
      locations: .init(fragments: ["t=\(start)"])
    )
  }
  
  /// Combine this MediaOverlayItem as a Text-based Locator, with an Audio-based Locator.
  /// This is generally used to report back a synchronizable Locator to Flutter client and backends.
  func toCombinedLocator(fromPlaybackLocator audioLocator: Locator) -> Locator? {
    guard var textLocator = self.asTextLocator else { return nil }
    // Combine the text-locator with given audio-locator's locations.
    // We keep the otherLocations("cssSelector") from text-locator.
    textLocator.locations = Locator.Locations(
      fragments: audioLocator.locations.fragments,
      progression: audioLocator.locations.progression,
      totalProgression: audioLocator.locations.totalProgression,
      position: audioLocator.locations.position,
      otherLocations: textLocator.locations.otherLocations,
    )
    return textLocator
  }
  
  // MARK: JSON
  static func fromJson(_ json: [String: Any], atPosition position: Int) -> FlutterMediaOverlayItem? {
    guard
      let audio = json["audio"] as? String, !audio.isEmpty,
      let text  = json["text"]  as? String, !text.isEmpty
    else { return nil }
    return FlutterMediaOverlayItem(audio: audio, text: text, position: position)
  }
}
