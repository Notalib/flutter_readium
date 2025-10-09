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

  Stream<Locator>? _onTextLocatorChanged;

  Stream<Locator>? _onAudioLocatorChanged;

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
  Future<void> setCustomHeaders(Map<String, String> headers) async {
    await methodChannel.invokeMethod<void>('setCustomHeaders', {'httpHeaders': headers});
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    final publicationString =
        await methodChannel.invokeMethod<String>('openPublication', [pubUrl]).then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }

  @override
  Future<void> closePublication(String pubIdentifier) async =>
      await methodChannel.invokeMethod<void>('closePublication', [pubIdentifier]);

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
  Future<void> ttsStart(Locator? fromLocator) async =>
      await methodChannel.invokeMethod('ttsStart', [fromLocator?.toJson()]);

  @override
  Future<void> ttsStop() async => await methodChannel.invokeMethod('ttsStop');

  @override
  Future<void> ttsPause() async => await methodChannel.invokeMethod('ttsPause');

  @override
  Future<void> ttsResume() async => await methodChannel.invokeMethod('ttsResume');

  @override
  Future<void> ttsNext() async => await methodChannel.invokeMethod('ttsNext');

  @override
  Future<void> ttsPrevious() async => await methodChannel.invokeMethod('ttsPrevious');

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
  Future<String?> getLinkContent(final String pubIdentifier, final Link link) =>
      methodChannel.invokeMethod<String>('getLinkContent', [pubIdentifier, jsonEncode(link.toJson())]);
}
