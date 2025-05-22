class TTSPreferences {
  TTSPreferences({
    this.speed,
    this.pitch,
    this.voiceIdentifier,
    this.languageOverride,
  });

  double? speed;
  double? pitch;
  String? voiceIdentifier;
  String? languageOverride;

  Map<String, dynamic> toMap() => {
        'speed': speed,
        'pitch': pitch,
        'voiceIdentifier': voiceIdentifier,
        'languageOverride': languageOverride,
      };
}
