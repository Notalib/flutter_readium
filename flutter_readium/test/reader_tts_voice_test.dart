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
    expect(voice.quality, TTSVoiceQuality.high);
  });
}
