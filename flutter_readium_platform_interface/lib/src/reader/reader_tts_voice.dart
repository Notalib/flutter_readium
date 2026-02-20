import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../enums.dart';
import '../utils/jsonable.dart';
import 'index.dart';

FimberLog _logger = FimberLog('ReaderTTSVoice');

@immutable
class ReaderTTSVoice with EquatableMixin implements JSONable {
  const ReaderTTSVoice._(
    this.identifier,
    this.name,
    this.language,
    this.networkRequired,
    this.gender,
    this.quality,
    this.active,
  );

  factory ReaderTTSVoice({
    required String identifier,
    required String name,
    required String language,
    required bool networkRequired,
    required TTSVoiceGender gender,
    required TTSVoiceQuality? quality,
    required bool? active,
  }) {
    // Enrich with full android voice name after creation.
    name = ReaderTTSVoiceUtils.getVoiceName(networkRequired, language, identifier, name);
    gender = ReaderTTSVoiceUtils.getVoiceGender(language, identifier, gender);

    return ReaderTTSVoice._(identifier, name, language, networkRequired, gender, quality, active);
  }

  factory ReaderTTSVoice.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final identifier = jsonObject.optString('identifier', remove: true);
    final name = jsonObject.optNullableString('name', remove: true) ?? identifier;
    final language = jsonObject.optString('language', remove: true);
    final networkRequired = jsonObject.optBoolean('networkRequired', remove: true);
    final active = jsonObject.optNullableBoolean('active', remove: true);

    final gender = TTSVoiceGender.fromString(jsonObject.optString('gender', remove: true));

    final qualityStr = jsonObject.optNullableString('quality', remove: true);
    TTSVoiceQuality? quality;

    if (qualityStr != null) {
      try {
        quality = TTSVoiceQuality.optFromString(qualityStr);
        if (quality == null) {
          _logger.w('Unknown TTSVoiceQuality value: $qualityStr, defaulting to null.');
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        _logger.w('Unknown TTSVoiceQuality value: $qualityStr, defaulting to null.', ex: e);
        quality = null;
      }
    }

    return ReaderTTSVoice(
      identifier: identifier,
      name: name,
      language: language,
      networkRequired: networkRequired,
      gender: gender,
      quality: quality,
      active: active,
    );
  }

  final String identifier;
  final String name;
  final String language;
  final bool networkRequired;
  final TTSVoiceGender gender;
  final TTSVoiceQuality? quality;
  final bool? active;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('identifier', identifier)
    ..put('name', name)
    ..put('language', language)
    ..put('networkRequired', networkRequired)
    ..put('gender', gender.name)
    ..putOpt('quality', quality?.name)
    ..putOpt('active', active);

  @override
  List<Object?> get props => [identifier, name, language, networkRequired, gender, quality, active];

  ReaderTTSVoice copyWith({
    String? identifier,
    String? name,
    String? language,
    bool? networkRequired,
    TTSVoiceGender? gender,
    TTSVoiceQuality? quality,
    bool? active,
  }) => ReaderTTSVoice(
    identifier: identifier ?? this.identifier,
    name: name ?? this.name,
    language: language ?? this.language,
    networkRequired: networkRequired ?? this.networkRequired,
    gender: gender ?? this.gender,
    quality: quality ?? this.quality,
    active: active ?? this.active,
  );
}

class ReaderTTSVoiceJsonConverter extends JsonConverter<ReaderTTSVoice, Map<String, dynamic>> {
  const ReaderTTSVoiceJsonConverter();

  @override
  ReaderTTSVoice fromJson(Map<String, dynamic> json) => ReaderTTSVoice.fromJson(json);

  @override
  Map<String, dynamic> toJson(ReaderTTSVoice voice) => voice.toJson();
}
