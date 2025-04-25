part of '../tts_audio_handler.dart';

extension TtsVoiceExtension on TtsAudioHandler {
  // This function gets all installed voices and maps them to ReadiumTtsVoice.
  // It checks if the voices have already been fetched, if they have, it returns the cached voices.
  // If the TTS is not initialized, it initializes it.
  // It fetches the TTS voices and if no voices are found, it throws an exception.
  // It initializes an empty list of ReadiumTtsVoice.
  // It iterates over each voice, fetching the locale and name of the voices.
  // If the locale or name is not a string, it skips the voice.
  // It adds a new ReadiumTtsVoice to the list with the locale and name.
  // It caches and returns the voices.
  Future<Iterable<ReadiumTtsVoice>> _getVoices() async {
    if (_voices != null) {
      return _voices!;
    }

    if (_tts == null) {
      await _initTts();
    }

    await _ensureGoogleTtsEngine();

    final ttsVoices = await _tts?.getVoices;

    if (ttsVoices == null || ttsVoices is! Iterable || ttsVoices.isEmpty) {
      throw const ReadiumException('No voices found on the device');
    }

    final voices = <ReadiumTtsVoice>[];

    for (final voice in ttsVoices) {
      final voiceLocaleRaw = voice['locale'];
      final name = voice['name'];

      if (voiceLocaleRaw is! String || name is! String) {
        continue;
      }

      voices.add(
        ReadiumTtsVoice(
          locale: voiceLocaleRaw,
          name: name,
        ),
      );
    }

    return _voices = voices;
  }

  // This function sets the language of the TTS.
  // It takes an optional language parameter.
  // If no language is provided, it fetches the publication language.
  // If the publication has no language, it logs a message and returns.
  // It fetches the TTS languages, and if no languages are found, it logs a message and returns.
  // It finds the TTS language that matches the publication language and if no matching language is found, it logs a message and returns.
  // It sets the TTS language.
  Future<void> _setLanguage([final String? lang]) async {
    final pubLang = lang ?? FlutterReadium.state.pubLang;

    if (pubLang == null) {
      R2Log.d('Publication has no language property');
      return;
    }

    final languages = await _tts?.getLanguages;

    if (languages == null || languages is! Iterable || languages.isEmpty) {
      R2Log.d('No language found on the device');
      return;
    }

    final ttsLang = languages.firstWhereOrNull((final lang) {
      final langString = lang.toString().toLowerCase();

      // Check if the language exist by complete Local as ex. en-GB.
      if (pubLang.contains('-')) {
        return langString == pubLang.toLowerCase();
      }

      // Publication language is only set as langCode - Try to find a best match.
      return pubLang == 'en'
          ? langString.endsWith('gb') || langString.endsWith('us')
          : langString.startsWith(pubLang);
    });

    if (ttsLang == null || ttsLang is! String) {
      R2Log.d('No language found - pubLang: $pubLang ttsLang: $ttsLang');
      return;
    }

    R2Log.d('Set language to $ttsLang');

    await _tts?.setLanguage(ttsLang);

    _currentVoiceIsAndroidNetwork = false;
  }

  // This function sets the language or voice of the TTS.
  // It looks for a voice that matches the language code.
  // If a matching voice is found, it sets the TTS voice to the matching voice.
  // Otherwise, it sets the TTS language to the language code.
  // It stores the language code as the last language.
  Future<void> _setLanguageOrVoice(
    final String? langCode,
    final List<ReadiumTtsVoice>? currentVoices,
  ) async {
    await _ensureGoogleTtsEngine();
    final matchingVoice =
        currentVoices?.firstWhereOrNull((final voice) => voice.langCode == langCode);

    if (Platform.isAndroid && matchingVoice == null) {
      final defaultVoice =
          defaultVoices.firstWhereOrNull((final voice) => voice.langCode == langCode);
      await setTtsVoice(defaultVoice ?? defaultVoices[0]);
    } else {
      await (matchingVoice != null ? setTtsVoice(matchingVoice) : _setLanguage(langCode));
    }

    _lastLang = langCode;
  }

  Future<void> _ensureGoogleTtsEngine() async {
    if (Platform.isAndroid) {
      final defaultEngine = await _tts?.getDefaultEngine;

      // Currently we only support Google's TTS engine on Android devices.
      const googleEngine = 'com.google.android.tts';

      if (defaultEngine == null || defaultEngine != googleEngine) {
        final engines = await _tts?.getEngines;

        if (engines == null || !engines.contains(googleEngine)) {
          // If Google TTS engine is not in the list, throw an exception.
          throw ReadiumException('Google TTS engine is not supported on device: $engines');
        }

        await _tts?.setEngine(googleEngine);
      }
    }
  }
}
