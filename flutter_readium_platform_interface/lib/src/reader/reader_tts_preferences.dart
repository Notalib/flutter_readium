import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../utils/jsonable.dart';
import '../utils/readium_log.dart';
import 'reader_audio_preferences.dart';

enum PageBreakBehavior {
  /// Pass page-break elements through unchanged — the raw label text is spoken.
  readAsIs,

  /// Rewrite the label with a localized prefix, e.g. "Page 42" or "side 42".
  prefixLabel,

  /// Filter page-break elements out of the iterator entirely.
  skip;

  static PageBreakBehavior? optFromString(final String? value) => PageBreakBehavior.values.firstWhereOrNull(
    (e) => e.name.toLowerCase() == value?.toLowerCase(),
  );
}

@immutable
class TTSPreferences with EquatableMixin implements JSONable {
  factory TTSPreferences.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final speed = jsonObject.optDouble('speed', remove: true);
    final pitch = jsonObject.optDouble('pitch', remove: true);
    final voiceIdentifier = jsonObject.optNullableString(
      'voiceIdentifier',
      remove: true,
    );
    final voicesJson = jsonObject.optJsonObject('voices', remove: true) ?? {};
    final voices = Map<String, String>.fromEntries(
      voicesJson.entries
          .where((entry) => entry.value is String)
          .map((entry) => MapEntry(entry.key, entry.value as String)),
    );
    final languageOverride = jsonObject.optNullableString(
      'languageOverride',
      remove: true,
    );
    final pageBreakBehavior = PageBreakBehavior.optFromString(
      jsonObject.remove('pageBreakBehavior') as String?,
    );
    final controlPanelInfoTypeStr = jsonObject.optNullableString(
      'controlPanelInfoType',
      remove: true,
    );
    ControlPanelInfoType? controlPanelInfoType;

    if (controlPanelInfoTypeStr != null) {
      controlPanelInfoType = ControlPanelInfoType.fromOptString(
        controlPanelInfoTypeStr,
      );
      if (controlPanelInfoType == null) {
        ReadiumLog.w(
          'Unknown ControlPanelInfoType value: $controlPanelInfoTypeStr, defaulting to ControlPanelInfoType.standard.',
        );
      }
    }

    return TTSPreferences(
      speed: speed,
      pitch: pitch,
      voiceIdentifier: voiceIdentifier,
      voices: voices,
      languageOverride: languageOverride,
      controlPanelInfoType: controlPanelInfoType ?? ControlPanelInfoType.standard,
      pageBreakBehavior: pageBreakBehavior,
    );
  }

  const TTSPreferences({
    this.speed,
    this.pitch,
    this.voiceIdentifier,
    this.voices = const {},
    this.languageOverride,
    this.controlPanelInfoType,
    this.pageBreakBehavior,
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

  /// How page-break elements are handled during TTS playback.
  /// When null, defaults to [PageBreakBehavior.readAsIs].
  final PageBreakBehavior? pageBreakBehavior;

  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('speed', speed)
    ..putOpt('pitch', pitch)
    ..putOpt('voiceIdentifier', voiceIdentifier)
    ..putMapIfNotEmpty('voices', voices)
    ..putOpt('languageOverride', languageOverride)
    ..putOpt('controlPanelInfoType', controlPanelInfoType?.toString().split('.').last)
    ..putOpt('pageBreakBehavior', pageBreakBehavior?.name);

  @override
  List<Object?> get props => [
    speed,
    pitch,
    voiceIdentifier,
    voices,
    languageOverride,
    controlPanelInfoType,
    pageBreakBehavior,
  ];
}
