import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';

import '../enums.dart';
import '../utils/jsonable.dart';
import 'index.dart';

class ReaderTTSVoice implements JSONable {
  const ReaderTTSVoice._(this.identifier, this.name, this.language, this.networkRequired, this.gender, this.quality);

  factory ReaderTTSVoice({
    required String identifier,
    required String name,
    required String language,
    required bool networkRequired,
    required TTSVoiceGender gender,
    required TTSVoiceQuality? quality,
  }) {
    // Enrich with full android voice name after creation.
    name = ReaderTTSVoiceNames.getVoiceName(networkRequired, language, identifier);
    return ReaderTTSVoice._(identifier, name, language, networkRequired, gender, quality);
  }

  factory ReaderTTSVoice.fromJson(final Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final identifier = jsonObject.optString('identifier', remove: true);
    final name = jsonObject.optString('name', remove: true);
    final language = jsonObject.optString('language', remove: true);
    final networkRequired = jsonObject.optBoolean('networkRequired', remove: true);
    final gender = jsonObject.optEnumFromString(
      'gender',
      TTSVoiceGender.values,
      fallback: TTSVoiceGender.unspecified,
      remove: true,
    )!;

    final qualityStr = jsonObject.optNullableString('quality', remove: true);
    TTSVoiceQuality? quality;

    if (qualityStr != null) {
      try {
        quality = TTSVoiceQuality.values.byName(qualityStr);
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        Fimber.w('Unknown TTSVoiceQuality value: $qualityStr, defaulting to null.', ex: e);
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
    );
  }

  final String identifier;
  final String name;
  final String language;
  final bool networkRequired;
  final TTSVoiceGender gender;
  final TTSVoiceQuality? quality;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'identifier': identifier,
    'name': name,
    'language': language,
    'networkRequired': networkRequired,
    'gender': gender.name,
    'quality': quality?.name,
  };
}

class ReaderTTSVoiceJsonConverter extends JsonConverter<ReaderTTSVoice, Map<String, dynamic>> {
  const ReaderTTSVoiceJsonConverter();

  @override
  ReaderTTSVoice fromJson(Map<String, dynamic> json) => ReaderTTSVoice.fromJson(json);

  @override
  Map<String, dynamic> toJson(ReaderTTSVoice voice) => voice.toJson();
}
