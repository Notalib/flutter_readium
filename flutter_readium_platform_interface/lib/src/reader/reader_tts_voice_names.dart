import 'dart:io';
import 'package:collection/collection.dart';

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

class ReaderTTSVoiceNames {
  static Map<String, List<ReadiumSpeechVoice>> voicesByLanguage = {};

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

  static String _androidName(final String language, final String identifier, final String? name) {
    // Start by looking up in the hardcoded mapping for known Android voices with non-descriptive names.
    final fromVoiceMapping = _voiceMappings[language]?[identifier];
    if (fromVoiceMapping != null) {
      return fromVoiceMapping;
    }

    // Lookup in the voices loaded from the Readium Speech repository for the requested language.
    final voices = voicesByLanguage[language.toLowerCase()]?.where((v) => v.os?.contains('android') == true).toList();
    if (voices == null || voices.isEmpty) {
      // Nothing found for this language, return the original name or identifier.
      return name ?? identifier;
    }

    // Find by identifier in nativeID, which contains the full Android voice name on Android.
    final byId = voices.firstWhereOrNull(
      (v) => v.nativeID?.where((id) => id.toLowerCase() == identifier.toLowerCase()).isNotEmpty == true,
    );

    if (byId != null) {
      return byId.label;
    }

    // Some Android voices have identifiers like "<lang-code>-language" and are not listed in nativeID.
    // We can find them in the altNames list.
    if (identifier.endsWith('-language')) {
      final byAltName = voices.firstWhereOrNull(
        (v) =>
            v.altNames?.where((altName) => altName.toLowerCase().endsWith(identifier.toLowerCase())).isNotEmpty == true,
      );

      if (byAltName != null) {
        return byAltName.label;
      }
    }

    // Nothing found, return the original name or identifier.
    return name ?? identifier;
  }
}
