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

    final cleared = voice.copyWith(label: null, gender: null, quality: null);

    expect(cleared.label, isNull);
    expect(cleared.gender, isNull);
    expect(cleared.quality, isNull);
  });
}
