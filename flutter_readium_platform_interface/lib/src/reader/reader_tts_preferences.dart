import 'package:fimber/fimber.dart';

import '../utils/jsonable.dart';
import 'reader_audio_preferences.dart';

class TTSPreferences implements JSONable {
  factory TTSPreferences.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final speed = jsonObject.optDouble('speed', remove: true);
    final pitch = jsonObject.optDouble('pitch', remove: true);
    final voiceIdentifier = jsonObject.optNullableString('voiceIdentifier', remove: true);
    final languageOverride = jsonObject.optNullableString('languageOverride', remove: true);
    final controlPanelInfoTypeStr = jsonObject.optNullableString('controlPanelInfoType', remove: true);
    ControlPanelInfoType? controlPanelInfoType;

    if (controlPanelInfoTypeStr != null) {
      try {
        controlPanelInfoType = ControlPanelInfoType.values.byName(controlPanelInfoTypeStr);
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        Fimber.w('Unknown ControlPanelInfoType value: $controlPanelInfoTypeStr, defaulting to null.', ex: e);
        controlPanelInfoType = null;
      }
    }

    return TTSPreferences(
      speed: speed,
      pitch: pitch,
      voiceIdentifier: voiceIdentifier,
      languageOverride: languageOverride,
      controlPanelInfoType: controlPanelInfoType,
    );
  }

  const TTSPreferences({
    this.speed,
    this.pitch,
    this.voiceIdentifier,
    this.languageOverride,
    this.controlPanelInfoType,
  });

  final double? speed;
  final double? pitch;
  final String? voiceIdentifier;
  final String? languageOverride;
  final ControlPanelInfoType? controlPanelInfoType;

  @override
  Map<String, dynamic> toJson() => {
    'speed': speed,
    'pitch': pitch,
    'voiceIdentifier': voiceIdentifier,
    'languageOverride': languageOverride,
    'controlPanelInfoType': controlPanelInfoType?.toString().split('.').last,
  };
}
