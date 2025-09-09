class AudioPreferences {
  AudioPreferences({
    this.volume,
    this.speed,
    this.pitch,
    this.seekInterval,
  });

  double? volume;
  double? speed;
  double? pitch;
  double? seekInterval;

  Map<String, dynamic> toMap() => {
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
        'seekInterval': seekInterval,
      };
}
