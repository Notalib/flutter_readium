import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../enums.dart';
import '../utils/constants.dart';
import '../utils/jsonable.dart';
import '../utils/readium_log.dart';
import 'index.dart';

@immutable
class ReaderTTSVoice with Equatable implements JSONable {
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
    name = ReaderTTSVoiceUtils.getVoiceName(language, identifier, name);
    gender = ReaderTTSVoiceUtils.getVoiceGender(language, identifier, gender);

    return ReaderTTSVoice._(
      identifier,
      name,
      language,
      networkRequired,
      gender,
      quality,
      active,
    );
  }

  factory ReaderTTSVoice.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final identifier = jsonObject.optString('identifier', remove: true);
    final name = jsonObject.optNullableString('name', remove: true) ?? identifier;
    final language = jsonObject.optString('language', remove: true);
    final networkRequired = jsonObject.optBoolean(
      'networkRequired',
      remove: true,
    );
    final active = jsonObject.optNullableBoolean('active', remove: true);

    final gender = TTSVoiceGender.fromString(
      jsonObject.optString('gender', remove: true),
    );

    final qualityStr = jsonObject.optNullableString('quality', remove: true);
    TTSVoiceQuality? quality;

    if (qualityStr != null) {
      try {
        quality = TTSVoiceQuality.optFromString(qualityStr);
        if (quality == null) {
          ReadiumLog.w(
            'Unknown TTSVoiceQuality value: $qualityStr, defaulting to null.',
          );
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        ReadiumLog.w(
          'Unknown TTSVoiceQuality value: $qualityStr, defaulting to null.',
        );
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
  List<Object?> get props => [
    identifier,
    name,
    language,
    networkRequired,
    gender,
    quality,
    active,
  ];

  ReaderTTSVoice copyWith({
    Object identifier = unset,
    Object name = unset,
    Object language = unset,
    Object networkRequired = unset,
    Object gender = unset,
    Object? quality = unset,
    Object? active = unset,
  }) => ReaderTTSVoice(
    identifier: identical(identifier, unset) ? this.identifier : (identifier as String),
    name: identical(name, unset) ? this.name : (name as String),
    language: identical(language, unset) ? this.language : (language as String),
    networkRequired: identical(networkRequired, unset) ? this.networkRequired : (networkRequired as bool),
    gender: identical(gender, unset) ? this.gender : (gender as TTSVoiceGender),
    quality: identical(quality, unset) ? this.quality : (quality as TTSVoiceQuality?),
    active: identical(active, unset) ? this.active : (active as bool?),
  );
}
