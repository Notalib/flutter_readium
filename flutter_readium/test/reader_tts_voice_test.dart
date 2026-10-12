import 'package:flutter/foundation.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ReaderTTSVoiceUtils.ensureReadiumVoiceDataLoaded);

  test('copyWith can clear enriched metadata', () {
    final voice = ReaderTTSVoice(
      identifier: 'en-us-x-iob-network',
      name: 'en-us-x-iob-network',
      language: 'en-US',
      networkRequired: true,
      active: false,
    );

    expect(voice.label, isNotNull);
    expect(voice.gender, TTSVoiceGender.female);
    expect(voice.quality, TTSVoiceQuality.high);

    final cleared = voice.copyWith(label: null, quality: null);

    expect(cleared.label, isNull);
    expect(cleared.gender, TTSVoiceGender.female);
    expect(cleared.quality, isNull);
  });

  for (final (name, language, gender) in [
    ('Zoe', 'en-US', TTSVoiceGender.male),
    ('Daniel', 'en-GB', TTSVoiceGender.female),
  ]) {
    test('reported ${gender.name} gender is preserved over conflicting catalog data', () {
      final voice = ReaderTTSVoice.fromJson({
        'identifier': '$name-uri',
        'name': name,
        'language': language,
        'networkRequired': false,
        'gender': gender.name,
      });

      expect(voice.label, name);
      expect(voice.gender, gender);
    });
  }

  for (final genderJson in <Map<String, Object?>>[
    {},
    {'gender': null},
    {'gender': 'unspecified'},
  ]) {
    final description = genderJson.isEmpty ? 'missing' : '${genderJson['gender']}';
    test('$description gender uses the catalog or remains unspecified without a match', () {
      final voice = ReaderTTSVoice.fromJson({
        'identifier': 'zoe-uri',
        'name': 'Zoe',
        'language': 'en-US',
        'networkRequired': false,
        ...genderJson,
      });
      final unknown = ReaderTTSVoice.fromJson({
        'identifier': 'unknown-uri',
        'name': 'Unknown Voice',
        'language': 'en-US',
        'networkRequired': false,
        ...genderJson,
      });

      expect(voice.gender, TTSVoiceGender.female);
      expect(unknown.gender, TTSVoiceGender.unspecified);
    });
  }

  test('Readium Speech veryHigh quality maps to highest', () {
    final voice = ReaderTTSVoice(
      identifier: 'christel-uri',
      name: 'Microsoft Christel Online (Natural) - Danish (Denmark)',
      language: 'da-DK',
      networkRequired: true,
      active: false,
    );

    expect(voice.label, 'Christel');
    expect(voice.quality, TTSVoiceQuality.highest);
  });

  test('iOS quality is not promoted to the best catalog variant', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final voice = ReaderTTSVoice.fromJson({
      'identifier': 'com.apple.voice.compact.en-US.Zoe',
      'name': 'Zoe',
      'language': 'en-US',
      'networkRequired': false,
      'quality': 'low',
    });

    expect(voice.label, 'Zoe');
    expect(voice.quality, TTSVoiceQuality.low);
  });

  test('iOS quality is not demoted by the catalog', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final voice = ReaderTTSVoice.fromJson({
      'identifier': 'samantha-uri',
      'name': 'Samantha',
      'language': 'en-US',
      'networkRequired': false,
      'quality': 'high',
    });

    expect(voice.label, 'Samantha');
    expect(voice.quality, TTSVoiceQuality.high);
  });

  test('hardcoded Android names take precedence over Readium Speech labels', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final voice = ReaderTTSVoice.fromJson({
      'identifier': 'da-dk-x-kfm-network',
      'name': 'da-dk-x-kfm-network',
      'language': 'da-DK',
      'networkRequired': true,
      'quality': 'normal',
    });

    expect(voice.name, 'Anna');
    expect(voice.label, 'Kvindestemme 1');
    expect(voice.quality, TTSVoiceQuality.normal);
  });
}
