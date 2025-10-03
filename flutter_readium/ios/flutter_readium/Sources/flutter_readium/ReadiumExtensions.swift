import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import ReadiumInternal

func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
    return min(max(value, minValue), maxValue)
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

extension TTSVoice {
  public var json: JSONDictionary.Wrapped {
      makeJSON([
        "identifier": identifier,
        "name": name,
        "gender": String.init(describing: gender),
        "quality": quality != nil ? String.init(describing: quality!) : nil,
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

public struct FlutterAudioPreferences {
  public var volume: Double?
  
  public var speed: Double?
  
  public var pitch: Double?
  
  public var seekInterval: Double?
    
  public var controlPanelInfoType: ControlPanelInfoType?
  
  public init(volume: Double = 1.0, rate: Double = 1.0, pitch: Double = 1.0, seekInterval: Double = 30, controlPanelInfoType: ControlPanelInfoType = ControlPanelInfoType.standard) {
    self.volume = volume
    self.speed = rate
    self.pitch = pitch
    self.seekInterval = seekInterval
    self.controlPanelInfoType = controlPanelInfoType
  }
  
  init(fromMap jsonMap: Dictionary<String, Any>) throws {
    let map = jsonMap,
        volume = map["volume"] as? Double ?? 1.0,
        rate = map["speed"] as? Double ?? 1.0,
        pitch = map["pitch"] as? Double ?? 1.0,
        seekInterval = map["seekInterval"] as? Double ?? 30

    let controlPanelInfoTypeStr = map["controlPanelInfoType"] as? String
    let mapControlPanelInfoType = controlPanelInfoTypeStr != nil ? ControlPanelInfoType(from: controlPanelInfoTypeStr!) : nil
    // TODO: Does audio prefs need to be clamped?
    let avRate = clamp(rate, minValue: 0.1, maxValue: 5.0)
    let avPitch = clamp(pitch, minValue: 0.5, maxValue: 2.0)
      self.init(volume: volume, rate: avRate, pitch: avPitch, seekInterval: seekInterval, controlPanelInfoType: mapControlPanelInfoType ?? .standard)
  }
}

public enum ControlPanelInfoType {
    case standard
    case standardWCh
    case chapterTitleAuthor
    case chapterTitle
    case titleChapter

    init?(from string: String) {
        switch string {
        case "standard": self = .standard
        case "standardWCh": self = .standardWCh
        case "chapterTitleAuthor": self = .chapterTitleAuthor
        case "chapterTitle": self = .chapterTitle
        case "titleChapter": self = .titleChapter
        default: return nil
        }
    }
}

public struct TTSPreferences {
  /// Rate at which utterances should be spoken. Defaults to 0.5
  public var rate: Float?

  /// Pitch at which utterances should be spoken. Defaults to 1.0 and should be in range 0.5 to 2.0
  public var pitch: Float?

  /// Language overriding the publication one.
  public var overrideLanguage: Language?

  /// Identifier for the voice used to speak the utterances.
  public var voiceIdentifier: String?

  public init(
    rate: Float? = nil,
    pitch: Float? = nil,
    overrideLanguage: Language? = nil,
    voiceIdentifier: String? = nil
  ) {
    self.rate = rate
    self.pitch = pitch
    self.overrideLanguage = overrideLanguage
    self.voiceIdentifier = voiceIdentifier
  }

  init(fromMap jsonMap: Dictionary<String, Any>) throws {
    let map = jsonMap,
        rate = map["speed"] as? Double ?? 1.0,
        pitch = map["pitch"] as? Double ?? 1.0,
        langCode = map["languageOverride"] as? String,
        overrideLanguage = langCode != nil ? Language(stringLiteral: langCode!) : nil,
        voiceIdentifier = map["voiceIdentifier"] as? String

    /// Rate is normalized on iOS, since AVSpeechUtterance has a default rate of 0.5 (see AVSpeechUtteranceDefaultSpeechRate)
    /// Rate is also clamped between allowed values.
    let avRate = clamp(Float(rate) * AVSpeechUtteranceDefaultSpeechRate,
                       minValue: AVSpeechUtteranceMinimumSpeechRate,
                       maxValue: AVSpeechUtteranceMaximumSpeechRate)
    /// Pitch is clamped between allowed values according to AVSpeechUtterance docs.
    let avPitch = clamp(Float(pitch),
                        minValue: 0.5,
                        maxValue: 2.0)
    self.init(rate: avRate, pitch: avPitch, overrideLanguage: overrideLanguage, voiceIdentifier: voiceIdentifier)
  }
}
