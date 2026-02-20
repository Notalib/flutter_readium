import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import '../index.dart';
import 'readium_speech_voice.dart';

// Hardcoded mappings for known Android TTS voices with non-descriptive names.
// These take precedence over those in Readium Speech.
// TODO: The identifiers are wrong and doesn't match anything at the moment.
final _voiceMappings = <String, Map<String, String>>{
  'da-DK': {'I': 'Anna', 'II': 'Jens', 'III': 'Clara', 'IV': 'Emma'},
  'en-US': {
    'I': 'Marilyn',
    'II': 'Betty',
    'III': 'Ellie',
    'IV': 'Mickey',
    'V': 'James',
    'VI': 'Samantha',
    'VII': 'Tom',
    'VIII': 'Daisy',
  },
  'en-GB': {'I': 'Stephen', 'II': 'Jane', 'III': 'Ian', 'IV': 'Maggie', 'V': 'Charles', 'VI': 'Amy'},
  'en-AU': {'I': 'Phoebe', 'II': 'Chris', 'III': 'Rachel', 'IV': 'Jack'},
};

const _voiceAssetPath = 'packages/flutter_readium/assets/voice_data/voices.json';

Map<String, List<ReadiumSpeechVoice>> _readiumVoiceData = {};

/// Utility functions for working with TTS voices, including loading and matching against the Readium Speech voice data.
abstract class ReaderTTSVoiceUtils {
  /// Ensure the Readium Speech voice data is loaded from the bundled asset before trying to match against it.
  static Future<void> ensureReadiumVoiceDataLoaded() async {
    if (!Platform.isAndroid) {
      // The voice data is currently only used to enrich Android voices with missing metadata, so we can skip loading it on other platforms.
      return;
    }

    if (_readiumVoiceData.isEmpty) {
      final jsonString = await rootBundle.loadString(_voiceAssetPath);
      final jsonList = jsonDecode(jsonString) as Map<String, dynamic>;
      final voices = jsonList
          .map((key, json) => MapEntry(key, ReadiumSpeechLanguage.fromJson(json as Map<String, dynamic>).voices))
          .values
          .reduce((acc, langVoices) => acc..addAll(langVoices))
          .toList();
      _readiumVoiceData = groupBy(voices, (v) => v.language.toLowerCase());
    }
  }

  /// Returns a user-friendly voice name for voices.
  static String getVoiceName(
    final bool networkRequired,
    final String language,
    final String identifier,
    final String? name,
  ) {
    if (Platform.isAndroid) {
      return _androidName(language, identifier, name);
    } else {
      return name ?? identifier;
    }
  }

  /// Resolve missing gender for Android voices by looking up in the Readium Speech data based on language and identifier.
  static TTSVoiceGender getVoiceGender(final String language, final String identifier, TTSVoiceGender fallback) {
    if (Platform.isAndroid) {
      final voice = findMatchingVoice(language, identifier);
      if (voice != null && voice.gender.isNotEmpty) {
        return TTSVoiceGender.optFromString(voice.gender) ?? fallback;
      }
    }
    return fallback;
  }

  static ReadiumSpeechVoice? findMatchingVoice(final String language, final String identifier) {
    // Lookup in the voices loaded from the Readium Speech repository for the requested language.
    final voices = _readiumVoiceData[language.toLowerCase()];
    if (voices == null || voices.isEmpty) {
      return null;
    }

    // Find by identifier in nativeID.
    final byId = voices.firstWhereOrNull(
      (v) => v.nativeID?.where((id) => id.toLowerCase() == identifier.toLowerCase()).isNotEmpty == true,
    );

    if (byId != null) {
      return byId;
    }

    // Some Android voices have identifiers like "<lang-code>-language" and are not listed in nativeID.
    // But we can find them in the altNames list.
    if (identifier.endsWith('-language')) {
      final byAltName = voices.firstWhereOrNull(
        (v) =>
            v.altNames?.where((altName) => altName.toLowerCase().endsWith(identifier.toLowerCase())).isNotEmpty == true,
      );

      if (byAltName != null) {
        return byAltName;
      }
    }

    return null;
  }

  static String _androidName(final String language, final String identifier, final String? name) {
    // Start by looking up in the hardcoded mapping for known Android voices with non-descriptive names.
    final fromVoiceMapping = _voiceMappings[language]?[identifier];
    if (fromVoiceMapping != null) {
      return fromVoiceMapping;
    }

    final voice = findMatchingVoice(language, identifier);
    if (voice != null) {
      return voice.label;
    }

    // Nothing found, return the original name or identifier.
    return name ?? identifier;
  }
}
