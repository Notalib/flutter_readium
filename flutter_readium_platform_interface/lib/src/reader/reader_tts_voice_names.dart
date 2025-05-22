import 'dart:io';

import 'index.dart';

// TODO: Map voices using Hadrien's excellent web-speech-voices
// See: https://github.com/HadrienGardeur/web-speech-recommended-voices/tree/main

class ReaderTTSVoiceNames {
  static String getVoiceName(final ReaderTTSVoice voiceModel) {
    if (Platform.isAndroid) {
      return androidFullVoiceName(voiceModel);
    } else {
      return voiceModel.name;
    }
  }

  static String androidFullVoiceName(final ReaderTTSVoice voiceModel) {
    final voiceName = androidName(voiceModel);
    if (voiceModel.networkRequired) {
      return '$voiceName (online)';
    } else {
      return voiceName;
    }
  }

  static String androidName(final ReaderTTSVoice voiceModel) {
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
      'en-GB': {
        'I': 'Stephen',
        'II': 'Jane',
        'III': 'Ian',
        'IV': 'Maggie',
        'V': 'Charles',
        'VI': 'Amy',
      },
      'en-AU': {'I': 'Phoebe', 'II': 'Chris', 'III': 'Rachel', 'IV': 'Jack'},
    };

    return voiceMappings[voiceModel.language]?[voiceModel.identifier] ?? voiceModel.identifier;
  }
}
