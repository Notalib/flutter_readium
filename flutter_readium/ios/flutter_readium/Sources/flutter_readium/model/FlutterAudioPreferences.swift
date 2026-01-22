public struct FlutterAudioPreferences {
  public var volume: Double

  public var speed: Double

  public var pitch: Double

  public var seekInterval: Double
  
  public var allowExternalSeeking: Bool

  public var controlPanelInfoType: ControlPanelInfoType
  
  public var updateIntervalSecs: TimeInterval

  public init(
    volume: Double = 1.0,
    rate: Double = 1.0,
    pitch: Double = 1.0,
    seekInterval: Double = 30,
    allowExternalSeeking: Bool = true,
    controlPanelInfoType: ControlPanelInfoType = ControlPanelInfoType.standard,
    updateIntervalSecs: TimeInterval = 0.2)
  {
    self.volume = volume
    self.speed = rate
    self.pitch = pitch
    self.seekInterval = seekInterval
    self.allowExternalSeeking = allowExternalSeeking
    self.controlPanelInfoType = controlPanelInfoType
    self.updateIntervalSecs = updateIntervalSecs
  }

  init(fromMap jsonMap: Dictionary<String, Any>) throws {
    let map = jsonMap,
        volume = map["volume"] as? Double ?? 1.0,
        rate = map["speed"] as? Double ?? 1.0,
        pitch = map["pitch"] as? Double ?? 1.0,
        seekInterval = map["seekInterval"] as? Double ?? 30,
        allowExternalSeeking = map["allowExternalSeeking"] as? Bool ?? true,
        updateIntervalSecs: TimeInterval = map["updateIntervalSecs"] as? TimeInterval ?? 0.2,
        controlPanelInfoType = ControlPanelInfoType(from: map["controlPanelInfoType"] as? String)

    let avRate = clamp(rate, minValue: 0.1, maxValue: 5.0)
    let avPitch = clamp(pitch, minValue: 0.5, maxValue: 2.0)
    self.init(volume: volume, rate: avRate, pitch: avPitch, seekInterval: seekInterval, allowExternalSeeking: allowExternalSeeking, controlPanelInfoType: controlPanelInfoType, updateIntervalSecs: updateIntervalSecs)
  }
}
