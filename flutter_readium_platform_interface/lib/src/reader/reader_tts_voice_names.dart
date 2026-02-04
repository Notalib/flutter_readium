import 'dart:io';

// TODO: Map voices using Hadrien's excellent web-speech-voices
// See: https://github.com/HadrienGardeur/web-speech-recommended-voices/tree/main

class ReaderTTSVoiceNames {
  static String getVoiceName(final bool networkRequired, final String language, final String identifier) {
    if (Platform.isAndroid) {
      return _androidFullVoiceName(networkRequired, language, identifier);
    } else {
      return identifier;
    }
  }

  static String _androidFullVoiceName(final bool networkRequired, final String language, final String identifier) {
    final voiceName = _androidName(language, identifier);
    if (networkRequired) {
      return '$voiceName (online)';
    } else {
      return voiceName;
    }
  }

  static String _androidName(final String language, final String identifier) {
    final voiceMappings = <String, Map<String, String>>{
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

    return voiceMappings[language]?[identifier] ?? identifier;
  }
}
