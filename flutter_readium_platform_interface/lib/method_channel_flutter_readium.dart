import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'flutter_readium_platform_interface.dart';

/// An implementation of [FlutterReadiumPlatform] that uses method channels.
class MethodChannelFlutterReadium extends FlutterReadiumPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  MethodChannel methodChannel = const MethodChannel('dk.nota.flutter_readium/main');

  /// The event channel used to receive text Locator changes from the native platform.
  @visibleForTesting
  EventChannel textLocatorChannel = const EventChannel('dk.nota.flutter_readium/text-locator');

  @visibleForTesting
  EventChannel audioLocatorChannel = const EventChannel('dk.nota.flutter_readium/audio-locator');

  /// The event channel used to receive text Locator changes from the native platform.
  @visibleForTesting
  EventChannel readerStatusChannel = const EventChannel('dk.nota.flutter_readium/reader-status');

  /// The event channel used to receive text Locator changes from the native platform.
  @visibleForTesting
  EventChannel isReadyChannel = const EventChannel('dk.nota.flutter_readium/is-ready');

  Stream<Locator>? _onTextLocatorChanged;

  Stream<Locator>? _onAudioLocatorChanged;

  Stream<ReadiumReaderStatus>? _onReaderStatusChanged;

  Stream<bool>? _isReadyStream;

  /// Fires whenever the Reader's current Locator changes.
  @override
  Stream<Locator> get onTextLocatorChanged {
    _onTextLocatorChanged ??= textLocatorChannel.receiveBroadcastStream().map((dynamic event) {
      final newLocator = Locator.fromJson(json.decode(event) as Map<String, dynamic>);
      return newLocator;
    });
    return _onTextLocatorChanged!;
  }

  /// Fires whenever the Audio Locator changes. Can be either TTS or pre-recorded.
  @override
  Stream<Locator> get onAudioLocatorChanged {
    _onAudioLocatorChanged ??= audioLocatorChannel.receiveBroadcastStream().map((dynamic event) {
      final newLocator = Locator.fromJson(json.decode(event) as Map<String, dynamic>);
      return newLocator;
    });
    return _onAudioLocatorChanged!;
  }

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    _onReaderStatusChanged ??= readerStatusChannel.receiveBroadcastStream().map((dynamic event) {
      final newStatus = ReadiumReaderStatus.values.firstWhere((e) => e.name == json.decode(event) as String);
      return newStatus;
    });
    return _onReaderStatusChanged!;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) async {
    final publicationString =
        await methodChannel.invokeMethod<String>('loadPublication', [pubUrl]).then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    final publicationString =
        await methodChannel.invokeMethod<String>('openPublication', [pubUrl]).then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }

  @override
  Stream<bool> get isReadyChanged {
    _isReadyStream ??= isReadyChannel.receiveBroadcastStream().map((dynamic event) => json.decode(event) as bool);
    return _isReadyStream!;
  }

  @override
  Future<void> closePublication() async => await methodChannel.invokeMethod<void>('closePublication');

  @override
  Future<void> goLeft() async => await currentReaderWidget?.goLeft();

  @override
  Future<void> goRight() async => await currentReaderWidget?.goRight();

  @override
  Future<void> skipToNext() async => await currentReaderWidget?.skipToNext();

  @override
  Future<void> skipToPrevious() async => await currentReaderWidget?.skipToPrevious();

  @override
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    defaultPreferences = preferences;
    await currentReaderWidget?.setEPUBPreferences(preferences);
  }

  @override
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async =>
      await currentReaderWidget?.applyDecorations(id, decorations);

  @override
  Future<void> ttsEnable(TTSPreferences? preferences) async =>
      await methodChannel.invokeMethod('ttsEnable', preferences?.toMap());

  @override
  Future<void> play(Locator? fromLocator) async => await methodChannel.invokeMethod('play', [fromLocator?.toJson()]);

  @override
  Future<void> stop() async => await methodChannel.invokeMethod('stop');

  @override
  Future<void> pause() async => await methodChannel.invokeMethod('pause');

  @override
  Future<void> resume() async => await methodChannel.invokeMethod('resume');

  @override
  Future<void> next() async => await methodChannel.invokeMethod('next');

  @override
  Future<void> previous() async => await methodChannel.invokeMethod('previous');

  @override
  Future<void> ttsSetDecorationStyle(
    ReaderDecorationStyle? utteranceDecoration,
    ReaderDecorationStyle? rangeDecoration,
  ) =>
      methodChannel.invokeMethod('ttsSetDecorationStyle', [utteranceDecoration?.toJson(), rangeDecoration?.toJson()]);

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    final voicesStr = await methodChannel.invokeMethod<List<dynamic>>('ttsGetAvailableVoices');
    final voices = voicesStr
            ?.cast<String>()
            .map<Map<String, dynamic>>((str) => json.decode(str) as Map<String, dynamic>)
            .map<ReaderTTSVoice>((map) => ReaderTTSVoice.fromJsonMap(map))
            .toList() ??
        <ReaderTTSVoice>[];
    return voices;
  }

  @override
  Future<void> ttsSetVoice(String voiceIdentifier, String? forLanguage) async {
    await methodChannel.invokeMethod('ttsSetVoice', [voiceIdentifier, forLanguage]);
  }

  @override
  Future<void> ttsSetPreferences(TTSPreferences preferences) =>
      methodChannel.invokeMethod('ttsSetPreferences', preferences.toMap());

  @override
  Future<String?> getLinkContent(final Link link) =>
      methodChannel.invokeMethod<String>('getLinkContent', [jsonEncode(link.toJson())]);

  @override
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      methodChannel.invokeMethod('audioEnable', [prefs?.toMap(), fromLocator?.toJson()]);

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) => methodChannel.invokeMethod('audioSetPreferences', prefs);
}
