import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import '../index.dart';

// Fallbacks for Android voices whose identifiers are not covered by Readium Speech.
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
  'en-gb': {
    'rjs': 'Stephen',
    'gba': 'Jane',
    'gbb': 'Ian',
    'gbc': 'Maggie',
    'gbd': 'Charles',
    'gbg': 'Amy',
  },
  'en-au': {'aua': 'Phoebe', 'aub': 'Chris', 'auc': 'Rachel', 'aud': 'Jack'},
};

const _voiceAssetPath = 'packages/flutter_readium/assets/voice_data/voices.json';

Map<String, List<ReadiumSpeechVoice>> _readiumVoiceData = {};

/// Utility functions for loading and matching Readium Speech voice metadata.
abstract class ReaderTTSVoiceUtils {
  /// Ensure the Readium Speech voice data is loaded from the bundled asset before trying to match against it.
  static Future<void> ensureReadiumVoiceDataLoaded() async {
    if (_readiumVoiceData.isEmpty) {
      try {
        final jsonString = await rootBundle.loadString(_voiceAssetPath);
        final jsonList = jsonDecode(jsonString) as Map<String, dynamic>;
        final voices = jsonList.values
            .expand(
              (json) => ReadiumSpeechLanguage.fromJson(
                json as Map<String, dynamic>,
              ).voices,
            )
            .toList();
        _readiumVoiceData = groupBy(voices, (v) => _normalizeLanguage(v.language));
      } on Object catch (error) {
        ReadiumLog.warn(
          'Could not load Readium Speech voice metadata; available voices '
          'will be returned without metadata. $error',
        );
      }
    }
  }

  /// Matches a platform voice to Readium Speech metadata for its language.
  static ReadiumSpeechVoice? matchVoiceData({
    required String language,
    required String identifier,
    required List<ReadiumSpeechVoice> voices,
    String? name,
  }) {
    final normalizedLanguage = _normalizeLanguage(language);
    final languageVoices = voices.where((voice) => _normalizeLanguage(voice.language) == normalizedLanguage).toList();

    if (name != null) {
      final byName = languageVoices.firstWhereOrNull(
        (voice) => voice.name.toLowerCase() == name.toLowerCase(),
      );
      if (byName != null) return byName;

      final byAltName = languageVoices.firstWhereOrNull(
        (voice) => voice.altNames?.any((alt) => alt.toLowerCase() == name.toLowerCase()) == true,
      );
      if (byAltName != null) return byAltName;
    }

    return languageVoices.firstWhereOrNull((voice) {
      final id = identifier.toLowerCase();
      return voice.name.toLowerCase() == id ||
          voice.nativeID?.any((nativeId) => nativeId.toLowerCase() == id) == true ||
          voice.altNames?.any((altName) {
                final alt = altName.toLowerCase();
                return alt == id || (id.endsWith('-language') && alt.endsWith(id));
              }) ==
              true;
    });
  }

  static String _normalizeLanguage(String language) => language.replaceAll('_', '-').toLowerCase();

  /// Returns Readium Speech metadata for a platform voice, if it is known.
  static ReadiumSpeechVoice? getVoiceMetadata(
    final String language,
    final String identifier,
    final String? name,
  ) => matchVoiceData(
    language: language,
    identifier: identifier,
    name: name,
    voices: _readiumVoiceData[_normalizeLanguage(language)] ?? const [],
  );

  /// Returns a friendly name for Android voices, preserving platform names elsewhere.
  static String getVoiceName(
    final String language,
    final String identifier,
    final String? name,
  ) {
    if (RuntimePlatform.isAndroid) {
      return _androidName(
        language,
        identifier,
        name,
        getVoiceMetadata(language, identifier, name),
      );
    }
    return name ?? identifier;
  }

  /// Look up the hardcoded friendly name for known Android voices based on the identifier.
  static String? _getAndroidVoiceNameFromIdentifier(
    final String language,
    final String identifier,
  ) {
    if (identifier.endsWith('-language')) {
      // Some Android voices have identifiers like "<lang-code>-language" and are not listed in nativeID.
      return null;
    }

    final mappings = _voiceMappings[language.toLowerCase()];
    if (mappings != null && mappings.isNotEmpty) {
      final identifierParts = identifier.toLowerCase().split('-').toSet();
      return mappings.entries
          .firstWhereOrNull(
            (e) => identifierParts.contains(e.key.toLowerCase()),
          )
          ?.value;
    }

    return null;
  }

  /// Get the voice name for Android voices.
  static String _androidName(
    final String language,
    final String identifier,
    final String? name,
    final ReadiumSpeechVoice? voice,
  ) {
    if (voice != null) {
      return voice.label;
    }

    final mappedName = _getAndroidVoiceNameFromIdentifier(language, identifier);
    if (mappedName != null && mappedName.isNotEmpty) return mappedName;

    // Nothing found, return the original name or identifier.
    return name ?? identifier;
  }
}
