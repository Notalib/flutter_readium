import '../../flutter_readium_platform_interface.dart';

class TTSPreferences {
  TTSPreferences({
    this.speed,
    this.pitch,
    this.voiceIdentifier,
    this.languageOverride,
    this.controlPanelInfoType,
  });

  double? speed;
  double? pitch;
  String? voiceIdentifier;
  String? languageOverride;
  ControlPanelInfoType? controlPanelInfoType;

  Map<String, dynamic> toMap() => {
        'speed': speed,
        'pitch': pitch,
        'voiceIdentifier': voiceIdentifier,
        'languageOverride': languageOverride,
        'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
      };
}
