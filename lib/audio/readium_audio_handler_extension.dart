import '../_index.dart';
import 'readium_audio_handler_custom_actions.dart';

extension ReadiumAudioHandlerExtension on AudioHandler {
  Future<void> skipToNextParagraph() =>
      customAction(ReadiumAudioHandlerCustomActions.skipToNextParagraph);

  Future<void> skipToPreviousParagraph() =>
      customAction(ReadiumAudioHandlerCustomActions.skipToPreviousParagraph);

  Future<void> go(final Locator locator) => customAction(
        ReadiumAudioHandlerCustomActions.go,
        {ReadiumAudioHandlerCustomActions.goPayloadKey: locator},
      );

  Future<void> pauseFade() => customAction(ReadiumAudioHandlerCustomActions.pauseFade);

  Future<void> cleanup() => customAction(ReadiumAudioHandlerCustomActions.cleanup);

  Future<List<ReadiumTtsVoice>> getTtsVoices({final List<String>? fallbackLang}) async {
    final voiceList = await customAction(
      ReadiumAudioHandlerCustomActions.getTtsVoices,
      {ReadiumAudioHandlerCustomActions.getTtsVoicesPayloadKey: fallbackLang},
    );
    return voiceList as List<ReadiumTtsVoice>;
  }

  Future<void> setTtsVoice(final ReadiumTtsVoice selectedVoice) => customAction(
        ReadiumAudioHandlerCustomActions.setTtsVoice,
        {ReadiumAudioHandlerCustomActions.setTtsVoicePayloadKey: selectedVoice},
      );
}
