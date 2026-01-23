import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';

export 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
export './reader_widget_switch.dart';

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

  Future<void> setCustomHeaders(Map<String, String> headers) {
    return _platform.setCustomHeaders(headers);
  }

  void setDefaultPreferences(EPUBPreferences preferences) {
    _platform.setDefaultPreferences(preferences);
  }

  Future<Publication> loadPublication(String pubUrl) {
    return _platform.loadPublication(pubUrl);
  }

  Future<Publication> openPublication(String pubUrl) {
    return _platform.openPublication(pubUrl).onError((err, _) {
      debugPrint('OpenPublication error: ${err.toString()}');
      throw ReadiumException.fromError(err);
    });
  }

  Future<void> closePublication() {
    return _platform.closePublication();
  }

  Stream<ReadiumReaderStatus> get onReaderStatusChanged => _platform.onReaderStatusChanged;

  Stream<Locator> get onTextLocatorChanged {
    return _platform.onTextLocatorChanged;
  }

  Stream<Locator> get onAudioLocatorChanged {
    return _platform.onAudioLocatorChanged;
  }

  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    return _platform.onTimebasedPlayerStateChanged;
  }

  Stream<ReadiumError> get onErrorEvent {
    return _platform.onErrorEvent;
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
  Future<void> ttsSetPreferences(TTSPreferences preferences) => _platform.ttsSetPreferences(preferences);
  Future<void> setDecorationStyle(ReaderDecorationStyle? utteranceDecoration, ReaderDecorationStyle? rangeDecoration) =>
      _platform.setDecorationStyle(utteranceDecoration, rangeDecoration);
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() => _platform.ttsGetAvailableVoices();
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) =>
      _platform.ttsSetVoice(voiceIdentifier, forLanguage);

  Future<void> play(Locator? fromLocator) => _platform.play(fromLocator);
  Future<void> stop() => _platform.stop();
  Future<void> pause() => _platform.pause();
  Future<void> resume() => _platform.resume();
  Future<void> next() => _platform.next();
  Future<void> previous() => _platform.previous();
  Future<bool> goToLocator(Locator locator) => _platform.goToLocator(locator);

  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      _platform.audioEnable(prefs: prefs, fromLocator: fromLocator);
  Future<void> audioSetPreferences(AudioPreferences prefs) => _platform.audioSetPreferences(prefs);

  Future<bool> goByLink(final Link link, final Publication pub) async {
    R2Log.d(() => 'Navigating to link: $link');

    final locator = pub.locatorFromLink(link);

    R2Log.d(locator);

    if (locator == null) {
      throw const ReadiumException('Link could not be resolved to locator');
    }

    return goToLocator(locator);
  }

  Future<bool> toPhysicalPageIndex(final String index, final Publication pub) async {
    final pageIndex = index.toLowerCase();
    final pageList = pub.pageList;
    final pageLink = pageList?.firstWhereOrNull(
      (final link) => link.title?.toLowerCase() == pageIndex,
    );
    if (pageLink == null) {
      throw const ReadiumException('Page link not found');
    }

    return goByLink(pageLink, pub);
  }
}
