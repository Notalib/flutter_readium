import 'dart:convert' show json;

import '../enums.dart';

class ReaderTTSVoice {
  ReaderTTSVoice({
    required this.identifier,
    required this.name,
    required this.language,
    required this.gender,
    required this.quality,
  });

  factory ReaderTTSVoice.fromJson(String jsonStr) => ReaderTTSVoice.fromJsonMap(json.decode(jsonStr));
  factory ReaderTTSVoice.fromJsonMap(final Map<String, dynamic> map) => ReaderTTSVoice(
        identifier: map['identifier'] as String,
        name: map['name'] as String,
        language: map['language'] as String,
        gender: TTSVoiceGender.values.byName(map['gender']),
        quality: map['quality'] is String ? TTSVoiceQuality.values.byName(map['quality']) : null,
      );

  String identifier;
  String name;
  String language;
  TTSVoiceGender gender;
  TTSVoiceQuality? quality;
}
