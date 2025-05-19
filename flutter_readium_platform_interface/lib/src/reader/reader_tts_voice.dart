import 'dart:convert' show json;

import '../enums.dart';
import 'index.dart';

class ReaderTTSVoice {
  ReaderTTSVoice({
    required this.identifier,
    required this.name,
    required this.language,
    required this.networkRequired,
    required this.gender,
    required this.quality,
  }) {
    // Enrich with full android voice name after creation.
    name = ReaderTTSVoiceNames.getVoiceName(this);
  }

  factory ReaderTTSVoice.fromJson(String jsonStr) => ReaderTTSVoice.fromJsonMap(json.decode(jsonStr));
  factory ReaderTTSVoice.fromJsonMap(final Map<String, dynamic> map) => ReaderTTSVoice(
        identifier: map['identifier'] as String,
        name: map['name'] is String ? map['name'] : '',
        language: map['language'] as String,
        networkRequired: map['networkRequired'] is String ? map['networkRequired'] == true : false,
        gender: map['gender'] is String ? TTSVoiceGender.values.byName(map['gender']) : TTSVoiceGender.unspecified,
        quality: map['quality'] is String ? TTSVoiceQuality.values.byName(map['quality']) : null,
      );

  String identifier;
  String name;
  String language;
  bool networkRequired;
  TTSVoiceGender gender;
  TTSVoiceQuality? quality;
}
