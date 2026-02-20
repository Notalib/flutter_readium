import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import '../index.dart';

// Hardcoded mappings for known Android TTS voices with non-descriptive names.
// These take precedence over those in Readium Speech.
// Android nativeID look like this:
//  - da-dk-x-kfm-local
//  - da-dk-x-kfm-network
//  - sv-se-x-lfs-network
// e.g. <lang-code>-x-<vid>-<network/local>, we use the <vid> part to map to a friendly name.
final _voiceMappings = <String, Map<String, String>>{
  'da-dk': {'kfm': 'Anna', 'nmm': 'Jens', 'sfp': 'Clara', 'vfb': 'Emma'},
  'en-us': {
    'sfg': 'Marilyn',
    'iob': 'Betty',
    'iog': 'Ellie',
    'iol': 'Mickey',
    'iom': 'James',
    'tpc': 'Samantha',
    'tpd': 'Tom',
    'tpf': 'Daisy',
  },
  'en-gb': {'rjs': 'Stephen', 'gba': 'Jane', 'gbb': 'Ian', 'gbc': 'Maggie', 'gbd': 'Charles', 'gbg': 'Amy'},
  'en-au': {'aua': 'Phoebe', 'aub': 'Chris', 'auc': 'Rachel', 'aud': 'Jack'},
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
  /// For android we need to resolve the name of the voice, we do that from the Readium Speech data unless we have a
  /// hardcoded mapping for that voice.
  static String getVoiceName(final String language, final String identifier, final String? name) {
    if (Platform.isAndroid) {
      return _androidName(language, identifier, name);
    } else {
      return name ?? identifier;
    }
  }

  /// Resolve the gender for the voice. For Android we look up in the Readium Speech data, for other platforms we trust
  /// the platform to provide it.
  static TTSVoiceGender getVoiceGender(final String language, final String identifier, TTSVoiceGender fallback) {
    if (Platform.isAndroid) {
      final voice = _findMatchingVoiceData(language, identifier);
      if (voice != null && voice.gender.isNotEmpty) {
        return TTSVoiceGender.optFromString(voice.gender) ?? fallback;
      }
    }

    return fallback;
  }

  /// Find a matching voice in the Readium Speech data for the given [language] and [identifier].
  static ReadiumSpeechVoice? _findMatchingVoiceData(final String language, final String identifier) {
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

  /// Look up the hardcoded friendly name for known Android voices based on the identifier.
  static String? _getAndroidVoiceNameFromIdentifier(final String language, final String identifier) {
    if (identifier.endsWith('-language')) {
      // Some Android voices have identifiers like "<lang-code>-language" and are not listed in nativeID.
      return null;
    }

    final mappings = _voiceMappings[language.toLowerCase()];
    if (mappings != null && mappings.isNotEmpty) {
      final identifierParts = identifier.toLowerCase().split('-').toSet();
      return mappings.entries.firstWhereOrNull((e) => identifierParts.contains(e.key.toLowerCase()))?.value;
    }

    return null;
  }

  /// Get the voice name for Android voices.
  static String _androidName(final String language, final String identifier, final String? name) {
    // Start by looking up in the hardcoded mapping for known Android voices with non-descriptive names.
    final mappedName = _getAndroidVoiceNameFromIdentifier(language, identifier);
    if (mappedName != null && mappedName.isNotEmpty) {
      return mappedName;
    }

    // Try finding the voice from the identifier.
    final voice = _findMatchingVoiceData(language, identifier);
    if (voice != null) {
      // We found a voice from the identifier, before using the label, check for a hardcoded friendly name.
      for (final nativeId in voice.nativeID ?? []) {
        final mappedName = _getAndroidVoiceNameFromIdentifier(language, nativeId);
        if (mappedName != null && mappedName.isNotEmpty) {
          return mappedName;
        }
      }

      return voice.label;
    }

    // Nothing found, return the original name or identifier.
    return name ?? identifier;
  }
}
