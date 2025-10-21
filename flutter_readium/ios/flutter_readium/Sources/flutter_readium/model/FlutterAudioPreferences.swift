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
    let mapControlPanelInfoType = ControlPanelInfoType(from: controlPanelInfoTypeStr)
    // TODO: Does audio prefs need to be clamped?
    let avRate = clamp(rate, minValue: 0.1, maxValue: 5.0)
    let avPitch = clamp(pitch, minValue: 0.5, maxValue: 2.0)
    self.init(volume: volume, rate: avRate, pitch: avPitch, seekInterval: seekInterval, controlPanelInfoType: mapControlPanelInfoType )
  }
}
