import Foundation

public struct FlutterAudioPreferences {
  public var volume: Double

  public var speed: Double

  public var pitch: Double

  public var seekInterval: Double

  public var continuousSeeking: Bool

  public var allowExternalSeeking: Bool

  public var controlPanelInfoType: ControlPanelInfoType

  public var controlPanelTimebase: ControlPanelTimebase

  public var updateIntervalSecs: TimeInterval

  public init(
    volume: Double = 1.0,
    rate: Double = 1.0,
    pitch: Double = 1.0,
    seekInterval: Double = 30,
    continuousSeeking: Bool = false,
    allowExternalSeeking: Bool = true,
    controlPanelInfoType: ControlPanelInfoType = ControlPanelInfoType.standard,
    controlPanelTimebase: ControlPanelTimebase = ControlPanelTimebase.chapter,
    updateIntervalSecs: TimeInterval = 0.2)
  {
    self.volume = volume
    self.speed = rate
    self.pitch = pitch
    self.seekInterval = seekInterval
    self.continuousSeeking = continuousSeeking
    self.allowExternalSeeking = allowExternalSeeking
    self.controlPanelInfoType = controlPanelInfoType
    self.controlPanelTimebase = controlPanelTimebase
    self.updateIntervalSecs = updateIntervalSecs
  }

  init(fromMap jsonMap: Dictionary<String, Any>) throws {
    let map = jsonMap,
        volume = map["volume"] as? Double ?? 1.0,
        rate = map["speed"] as? Double ?? 1.0,
        pitch = map["pitch"] as? Double ?? 1.0,
        seekInterval = map["seekInterval"] as? Double ?? 30,
        continuousSeeking = map["continuousSeeking"] as? Bool ?? false,
        allowExternalSeeking = map["allowExternalSeeking"] as? Bool ?? true,
        updateIntervalSecs: TimeInterval = map["updateIntervalSecs"] as? TimeInterval ?? 0.2,
        controlPanelInfoType = ControlPanelInfoType(from: map["controlPanelInfoType"] as? String),
        controlPanelTimebase = ControlPanelTimebase(from: map["controlPanelTimebase"] as? String)

    let avRate = clamp(rate, minValue: 0.1, maxValue: 5.0)
    let avPitch = clamp(pitch, minValue: 0.5, maxValue: 2.0)
    self.init(volume: volume, rate: avRate, pitch: avPitch, seekInterval: seekInterval, continuousSeeking: continuousSeeking, allowExternalSeeking: allowExternalSeeking, controlPanelInfoType: controlPanelInfoType, controlPanelTimebase: controlPanelTimebase, updateIntervalSecs: updateIntervalSecs)
  }
}
