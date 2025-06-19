import 'dart:async';

import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

class FlutterReadium {
  /// Constructs a singleton instance of [FlutterReadium].
  factory FlutterReadium() {
    _singleton ??= FlutterReadium._();
    return _singleton!;
  }

  FlutterReadium._();

  static FlutterReadium? _singleton;

  static FlutterReadiumPlatform get _platform {
    return FlutterReadiumPlatform.instance;
  }

  Future<Publication> openPublication(String pubUrl) {
    return _platform.openPublication(pubUrl);
  }

  Future<void> closePublication(String pubUrl) {
    return _platform.closePublication(pubUrl);
  }

  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _platform.onReaderStatusChanged;

  Stream<Locator> get onTextLocatorChanged {
    return _platform.onTextLocatorChanged;
  }

  Stream<Locator> get onAudioLocatorChanged {
    return _platform.onAudioLocatorChanged;
  }

  Future<void> goLeft() {
    return _platform.goLeft();
  }

  Future<void> goRight() {
    return _platform.goRight();
  }

  Future<void> skipToNext() {
    return _platform.skipToNext();
  }

  Future<void> skipToPrevious() {
    return _platform.skipToPrevious();
  }

  Future<void> setEPUBPreferences(EPUBPreferences preferences) => _platform.setEPUBPreferences(preferences);

  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) =>
      _platform.applyDecorations(id, decorations);

  Future<void> ttsEnable(TTSPreferences? preferences) => _platform.ttsEnable(preferences);
  Future<void> ttsStart(Locator? fromLocator) => _platform.ttsStart(fromLocator);
  Future<void> ttsStop() => _platform.ttsStop();
  Future<void> ttsPause() => _platform.ttsPause();
  Future<void> ttsResume() => _platform.ttsResume();
  Future<void> ttsNext() => _platform.ttsNext();
  Future<void> ttsPrevious() => _platform.ttsPrevious();
  Future<void> ttsSetPreferences(TTSPreferences preferences) => _platform.ttsSetPreferences(preferences);
  Future<void> ttsSetDecorationStyle(
          ReaderDecorationStyle? utteranceDecoration, ReaderDecorationStyle? rangeDecoration) =>
      _platform.ttsSetDecorationStyle(utteranceDecoration, rangeDecoration);
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() => _platform.ttsGetAvailableVoices();
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) => _platform.ttsSetVoice(voiceIdentifier, forLanguage);
}
