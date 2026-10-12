import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../enums.dart';
import '../utils/constants.dart';
import '../utils/jsonable.dart';
import 'index.dart';

@immutable
class ReaderTTSVoice with Equatable implements JSONable {
  const ReaderTTSVoice._(
    this.identifier,
    this.name,
    this.language,
    this.networkRequired,
    this.label,
    this.gender,
    this.quality,
    this.active,
  );

  factory ReaderTTSVoice({
    required String identifier,
    required String name,
    required String language,
    required bool networkRequired,
    required bool? active,
    String? label,
    TTSVoiceGender gender = TTSVoiceGender.unspecified,
    TTSVoiceQuality? quality,
  }) {
    final metadata = ReaderTTSVoiceUtils.getVoiceMetadata(
      language,
      identifier,
      name,
    );

    // Catalog quality covers multiple variants; preserve the quality of the installed voice.
    name = ReaderTTSVoiceUtils.getVoiceName(language, identifier, name);
    label ??= metadata?.label;
    gender = TTSVoiceGender.optFromString(metadata?.gender ?? '') ?? gender;
    quality ??= _readiumQuality(metadata?.quality ?? const []);

    return ReaderTTSVoice._(
      identifier,
      name,
      language,
      networkRequired,
      label,
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
    final label = jsonObject.optNullableString('label', remove: true);
    final gender = TTSVoiceGender.fromString(jsonObject.optString('gender', remove: true));
    final quality = TTSVoiceQuality.optFromString(jsonObject.optString('quality', remove: true));
    final active = jsonObject.optNullableBoolean('active', remove: true);
    return ReaderTTSVoice(
      identifier: identifier,
      name: name,
      language: language,
      networkRequired: networkRequired,
      label: label,
      gender: gender,
      quality: quality,
      active: active,
    );
  }

  final String identifier;
  final String name;
  final String language;
  final bool networkRequired;
  final String? label;
  final TTSVoiceGender gender;
  final TTSVoiceQuality? quality;
  final bool? active;

  @override
  Map<String, dynamic> toJson() => {}
    ..put('identifier', identifier)
    ..put('name', name)
    ..put('language', language)
    ..put('networkRequired', networkRequired)
    ..putOpt('label', label)
    ..put('gender', gender.name)
    ..putOpt('quality', quality?.name)
    ..putOpt('active', active);

  @override
  List<Object?> get props => [
    identifier,
    name,
    language,
    networkRequired,
    label,
    gender,
    quality,
    active,
  ];

  ReaderTTSVoice copyWith({
    Object identifier = unset,
    Object name = unset,
    Object language = unset,
    Object networkRequired = unset,
    Object? label = unset,
    Object gender = unset,
    Object? quality = unset,
    Object? active = unset,
  }) => ReaderTTSVoice._(
    identical(identifier, unset) ? this.identifier : (identifier as String),
    identical(name, unset) ? this.name : (name as String),
    identical(language, unset) ? this.language : (language as String),
    identical(networkRequired, unset) ? this.networkRequired : (networkRequired as bool),
    identical(label, unset) ? this.label : (label as String?),
    identical(gender, unset) ? this.gender : (gender as TTSVoiceGender),
    identical(quality, unset) ? this.quality : (quality as TTSVoiceQuality?),
    identical(active, unset) ? this.active : (active as bool?),
  );
}

// Readium Speech lists every quality a voice ships in; pick the best. Its `veryHigh` is our `highest`.
TTSVoiceQuality? _readiumQuality(List<String> qualities) {
  const preference = {
    'veryhigh': TTSVoiceQuality.highest,
    'high': TTSVoiceQuality.high,
    'normal': TTSVoiceQuality.normal,
    'low': TTSVoiceQuality.low,
  };
  final lower = qualities.map((q) => q.toLowerCase()).toSet();
  return preference.entries.firstWhereOrNull((e) => lower.contains(e.key))?.value;
}
