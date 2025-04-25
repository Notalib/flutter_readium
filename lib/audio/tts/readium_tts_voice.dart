import 'dart:io';
import 'dart:ui';

import '../../_index.dart';

part 'readium_tts_voice.freezed.dart';
part 'readium_tts_voice.g.dart';

@freezedExcludeUnion
abstract class ReadiumTtsVoice with _$ReadiumTtsVoice {
  const factory ReadiumTtsVoice({
    required final String locale,
    required final String name,
  }) = _ReadiumTtsVoice;

  factory ReadiumTtsVoice.fromJson(final Map<String, dynamic> json) =>
      _$ReadiumTtsVoiceFromJson(json);
}

extension ReadiumTtsVoiceExtension on ReadiumTtsVoice {
  Locale get localeObj => locale.toLocale();

  String get langCode => localeObj.languageCode;

  // Android voices have a different name format than what we receive, making it more readable
  String? get androidVoiceName => Platform.isAndroid ? _androidTtsVoiceName(name) : null;

  // Identifying bool for if the voice is local or network or not one of the standards.
  bool? get androidIsLocal => Platform.isAndroid ? _androidIsLocal(name) : null;

  // Funtion to map the voice name to the correct voice name for Android
  // These are only for the languages we know and might not be correct, as it is not always easy to hear which are the correct matches.
  String _androidTtsVoiceName(final String name) {
    final voiceMap = {
      'I': [
        'kfm',
        'rjs',
        'aua',
        'sfg',
        'vlf',
        'caa',
        'nhf',
        'eea',
        'tfb',
        'lfs',
        'sfb',
        'arc',
        'isf',
        'ssa',
        'jab',
        'kda',
        'dfc',
        'jfb',
        'rfj',
        'caf',
        'heb',
      ],
      'II': [
        'nmm',
        'gba',
        'aub',
        'iob',
        'fra',
        'cab',
        'dea',
        'eec',
        'bmh',
        'afp',
        'esc',
        'ard',
        'ccd',
        'htm',
        'itb',
        'ruc',
        'jmn',
        'cfl',
        'hec',
      ],
      'III': [
        'sfp',
        'gbb',
        'auc',
        'iog',
        'frb',
        'cac',
        'deb',
        'eed',
        'dma',
        'cfg',
        'esd',
        'are',
        'cce',
        'jac',
        'itc',
        'rud',
        'pmj',
        'cmj',
        'hed',
      ],
      'IV': [
        'vfb',
        'gbc',
        'aud',
        'iol',
        'frc',
        'cad',
        'deg',
        'eee',
        'lfc',
        'cmh',
        'esf',
        'arz',
        'ccc',
        'jad',
        'itd',
        'rue',
        'sfs',
        'tfs',
        'hee',
      ],
      'V': [
        'gbd',
        'iom',
        'frd',
        'eef',
        'yfr',
        'dmc',
        'ruf',
        'tmg',
      ],
      'VI': ['gbg', 'tpc'],
      'VII': ['tpd'],
      'VIII': ['tpf'],
    };

    for (final entry in voiceMap.entries) {
      if (entry.value.any((final key) => name.contains(key))) {
        return entry.key;
      }
    }

    return name;
  }

  bool? _androidIsLocal(final String name) {
    if (name.contains('local')) {
      return true;
    } else if (name.contains('network')) {
      return false;
    } else {
      return null;
    }
  }
}
