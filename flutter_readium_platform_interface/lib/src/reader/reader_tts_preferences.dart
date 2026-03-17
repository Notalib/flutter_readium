import 'package:fimber/fimber.dart';

import '../utils/jsonable.dart';
import 'reader_audio_preferences.dart';

class TTSPreferences implements JSONable {
  factory TTSPreferences.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final speed = jsonObject.optDouble('speed', remove: true);
    final pitch = jsonObject.optDouble('pitch', remove: true);
    final voiceIdentifier = jsonObject.optNullableString('voiceIdentifier', remove: true);
    final voicesJson = jsonObject.optJsonObject('voices', remove: true) ?? {};
    final voices = voicesJson.map((key, value) => MapEntry(key, value.toString()));
    final languageOverride = jsonObject.optNullableString('languageOverride', remove: true);
    final controlPanelInfoTypeStr = jsonObject.optNullableString('controlPanelInfoType', remove: true);
    ControlPanelInfoType? controlPanelInfoType;

    if (controlPanelInfoTypeStr != null) {
      try {
        controlPanelInfoType = ControlPanelInfoType.fromOptString(controlPanelInfoTypeStr);
      } catch (e) {
        Fimber.w('Unknown ControlPanelInfoType value: $controlPanelInfoTypeStr, defaulting to null.', ex: e);
        controlPanelInfoType = null;
      }
    }

    return TTSPreferences(
      speed: speed,
      pitch: pitch,
      voiceIdentifier: voiceIdentifier,
      voices: voices,
      languageOverride: languageOverride,
      controlPanelInfoType: controlPanelInfoType ?? ControlPanelInfoType.standard,
    );
  }

  const TTSPreferences({
    this.speed,
    this.pitch,
    this.voiceIdentifier,
    this.voices = const {},
    this.languageOverride,
    this.controlPanelInfoType,
  });

  /// The speech rate (speed) for text-to-speech. A value of 1.0 is the normal speed, less than 1.0 is slower, and greater than 1.0 is faster.
  final double? speed;

  /// The pitch for text-to-speech. A value of 1.0 is the normal pitch, less than 1.0 is lower, and greater than 1.0 is higher.
  final double? pitch;

  /// The identifier of the voice to use for text-to-speech. This should correspond to one of the available voices returned by [ttsGetAvailableVoices].
  final String? voiceIdentifier;

  /// More detailed voice settings for Android, where you can set a voice per language.
  final Map<String, String> voices;

  /// Force language for TTS, ignoring the language specified in the publication.
  final String? languageOverride;

  /// Control panel info type to determine what information is sent to the control panel during TTS playback.
  final ControlPanelInfoType? controlPanelInfoType;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('speed', speed)
    ..putOpt('pitch', pitch)
    ..putOpt('voiceIdentifier', voiceIdentifier)
    ..putMapIfNotEmpty('voices', voices)
    ..putOpt('languageOverride', languageOverride)
    ..putOpt('controlPanelInfoType', controlPanelInfoType?.toString().split('.').last);
}
