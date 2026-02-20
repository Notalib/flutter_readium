import 'package:equatable/equatable.dart';

import '../../flutter_readium_platform_interface.dart';

/// Represents a speech language with its associated TTS voices from the Readium Speech repository.
/// See: https://github.com/readium/speech
class ReadiumSpeechLanguage with EquatableMixin implements JSONable {
  factory ReadiumSpeechLanguage.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);
    final language = jsonObject.optString('language', remove: true);
    final defaultRegion = jsonObject.optString('defaultRegion', remove: true);
    final testUtterance = jsonObject.optString('testUtterance', remove: true);
    final voicesJson = jsonObject.optJsonArray('voices', remove: true) ?? [];
    final voices = voicesJson.cast<Map<String, dynamic>>().map((e) => ReadiumSpeechVoice.fromJson(e)).toList();

    return ReadiumSpeechLanguage(
      language: language,
      defaultRegion: defaultRegion,
      testUtterance: testUtterance,
      voices: voices,
    );
  }

  const ReadiumSpeechLanguage({
    required this.language,
    required this.defaultRegion,
    required this.testUtterance,
    required this.voices,
  });

  final String language;
  final String defaultRegion;
  final String testUtterance;
  final List<ReadiumSpeechVoice> voices;

  @override
  List<Object?> get props => [language, defaultRegion, testUtterance, voices];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('language', language)
    ..put('defaultRegion', defaultRegion)
    ..put('testUtterance', testUtterance)
    ..putIterableIfNotEmpty('voices', voices);
}
