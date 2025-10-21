import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import ReadiumInternal

public struct TTSPreferences {
  /// Rate at which utterances should be spoken. Defaults to 0.5
  public var rate: Float?

  /// Pitch at which utterances should be spoken. Defaults to 1.0 and should be in range 0.5 to 2.0
  public var pitch: Float?

  /// Language overriding the publication one.
  public var overrideLanguage: Language?

  /// Identifier for the voice used to speak the utterances.
  public var voiceIdentifier: String?

  public var controlPanelInfoType: ControlPanelInfoType?

  public init(
    rate: Float? = nil,
    pitch: Float? = nil,
    overrideLanguage: Language? = nil,
    voiceIdentifier: String? = nil,
    controlPanelInfoType: ControlPanelInfoType = .standard
  ) {
    self.rate = rate
    self.pitch = pitch
    self.overrideLanguage = overrideLanguage
    self.voiceIdentifier = voiceIdentifier
    self.controlPanelInfoType = controlPanelInfoType
  }

  init(fromMap jsonMap: Dictionary<String, Any>) throws {
    let map = jsonMap,
        rate = map["speed"] as? Double ?? 1.0,
        pitch = map["pitch"] as? Double ?? 1.0,
        langCode = map["languageOverride"] as? String,
        overrideLanguage = langCode != nil ? Language(stringLiteral: langCode!) : nil,
        voiceIdentifier = map["voiceIdentifier"] as? String

    let controlPanelInfoTypeStr = map["controlPanelInfoType"] as? String
    let mapControlPanelInfoType = ControlPanelInfoType(from: controlPanelInfoTypeStr)
    /// Rate is normalized on iOS, since AVSpeechUtterance has a default rate of 0.5 (see AVSpeechUtteranceDefaultSpeechRate)
    /// Rate is also clamped between allowed values.
    let avRate = clamp(Float(rate) * AVSpeechUtteranceDefaultSpeechRate,
                       minValue: AVSpeechUtteranceMinimumSpeechRate,
                       maxValue: AVSpeechUtteranceMaximumSpeechRate)
    /// Pitch is clamped between allowed values according to AVSpeechUtterance docs.
    let avPitch = clamp(Float(pitch),
                        minValue: 0.5,
                        maxValue: 2.0)
    self.init(rate: avRate, pitch: avPitch, overrideLanguage: overrideLanguage, voiceIdentifier: voiceIdentifier, controlPanelInfoType: mapControlPanelInfoType)
  }
}
