import 'dart:convert';

import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final voices = ReadiumSpeechLanguage.fromJson(
    jsonDecode('''
      {
        "language": "en-US",
        "defaultRegion": "US",
        "testUtterance": "Hello",
        "voices": [
          {
            "label": "Ava",
            "name": "Microsoft Ava Online (Natural) - English (United States)",
            "language": "en-US",
            "gender": "female",
            "quality": ["normal", "high"],
            "altNames": ["Ava Natural"],
            "nativeID": ["en-us-ava"]
          }
        ]
      }
    ''')
        as Map<String, dynamic>,
  ).voices;

  group('ReaderTTSVoiceUtils.matchVoiceData', () {
    test('matches a platform name', () {
      final voice = ReaderTTSVoiceUtils.matchVoiceData(
        language: 'en-us',
        identifier: 'some-uri',
        name: 'Microsoft Ava Online (Natural) - English (United States)',
        voices: voices,
      );

      expect(voice?.label, 'Ava');
    });

    test('matches an alternate name', () {
      final voice = ReaderTTSVoiceUtils.matchVoiceData(
        language: 'en-US',
        identifier: 'some-uri',
        name: 'Ava Natural',
        voices: voices,
      );

      expect(voice?.label, 'Ava');
    });

    test('matches an identifier', () {
      final voice = ReaderTTSVoiceUtils.matchVoiceData(
        language: 'en-US',
        identifier: 'en-us-ava',
        voices: voices,
      );

      expect(voice?.label, 'Ava');
    });

    test('keeps an unknown voice unmatched and scopes matching by language', () {
      final voice = ReaderTTSVoiceUtils.matchVoiceData(
        language: 'en-GB',
        identifier: 'en-us-ava',
        name: 'Microsoft Ava Online (Natural) - English (United States)',
        voices: voices,
      );

      expect(voice, isNull);
    });
  });

  test('an unrecognized platform voice keeps null Readium metadata', () {
    final voice = ReaderTTSVoice.fromJson({
      'identifier': 'unknown-uri',
      'name': 'Unknown Voice',
      'language': 'en-GB',
      'networkRequired': false,
      'gender': 'female',
      'quality': 'high',
    });

    expect(voice.name, 'Unknown Voice');
    expect(voice.label, isNull);
    expect(voice.gender, isNull);
    expect(voice.quality, isNull);
  });

  test('ReaderTTSVoice serializes and copies the friendly label', () {
    final voice = ReaderTTSVoice(
      identifier: 'ava-uri',
      name: 'Ava',
      language: 'en-US',
      networkRequired: false,
      active: true,
      label: 'Friendly Ava',
    );

    final restored = ReaderTTSVoice.fromJson(voice.toJson());
    final updated = voice.copyWith(label: 'Updated Ava');

    expect(restored.label, 'Friendly Ava');
    expect(voice.copyWith().label, 'Friendly Ava');
    expect(updated.label, 'Updated Ava');
  });
}
