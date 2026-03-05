import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  EventChannel timebasedStateChannel = const EventChannel('dk.nota.flutter_readium/timebased-state');

  @visibleForTesting
  EventChannel errorEventChannel = const EventChannel('dk.nota.flutter_readium/error');

  /// The event channel used to receive text Locator changes from the native platform.
  @visibleForTesting
  EventChannel readerStatusChannel = const EventChannel('dk.nota.flutter_readium/reader-status');

  Stream<Locator>? _onTextLocatorChanged;

  Stream<ReadiumTimebasedState>? _onTimebasedPlayerStateChanged;

  Stream<ReadiumReaderStatus>? _onReaderStatusChanged;

  Stream<ReadiumError>? _onErrorEvent;

  /// Fires whenever the Reader's current Locator changes.
  @override
  Stream<Locator> get onTextLocatorChanged {
    _onTextLocatorChanged ??= textLocatorChannel.receiveBroadcastStream().map((dynamic event) {
      final newLocator = Locator.fromJson(json.decode(event) as Map<String, dynamic>);
      return newLocator!;
    });
    return _onTextLocatorChanged!;
  }

  /// Fires whenever the TimebasedNavigator changes state
  @override
  Stream<ReadiumTimebasedState> get onTimebasedPlayerStateChanged {
    _onTimebasedPlayerStateChanged ??= timebasedStateChannel.receiveBroadcastStream().map((dynamic event) {
      final state = ReadiumTimebasedState.fromJson(json.decode(event) as Map<String, dynamic>);
      return state;
    });
    return _onTimebasedPlayerStateChanged!;
  }

  @override
  Stream<ReadiumReaderStatus> get onReaderStatusChanged {
    _onReaderStatusChanged ??= readerStatusChannel.receiveBroadcastStream().map((dynamic event) {
      debugPrint('Received reader status event: $event');
      try {
        return ReadiumReaderStatus.fromString(json.decode(event) as String) ??
            ReadiumReaderStatus.fromString(event) ??
            ReadiumReaderStatus.error;
      } catch (e) {
        debugPrint('Error parsing reader status event: $e');
        return ReadiumReaderStatus.error;
      }
    });
    return _onReaderStatusChanged!;
  }

  @override
  Stream<ReadiumError> get onErrorEvent {
    _onErrorEvent ??= errorEventChannel.receiveBroadcastStream().map((dynamic event) {
      final errorEvent = json.decode(event) as ReadiumError;
      return errorEvent;
    });
    return _onErrorEvent!;
  }

  @override
  Future<Publication> loadPublication(String pubUrl) async {
    final publicationString = await methodChannel
        .invokeMethod<String>('loadPublication', [pubUrl])
        .then<String>((dynamic result) => result);

    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>)!;
  }

  @override
  Future<void> setCustomHeaders(Map<String, String> headers) async {
    await methodChannel.invokeMethod<void>('setCustomHeaders', {'httpHeaders': headers});
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    final publicationString = await methodChannel
        .invokeMethod<String>('openPublication', [pubUrl])
        .then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>)!;
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
  Future<bool> goToLocator(Locator locator) async =>
      await methodChannel.invokeMethod<bool>('goToLocator', [locator.toJson()]) ?? false;

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
      await methodChannel.invokeMethod('ttsEnable', preferences?.toJson());

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
  Future<void> setDecorationStyle(ReaderDecorationStyle? utteranceDecoration, ReaderDecorationStyle? rangeDecoration) =>
      methodChannel.invokeMethod('setDecorationStyle', [utteranceDecoration?.toJson(), rangeDecoration?.toJson()]);

  @override
  Future<List<ReaderTTSVoice>> ttsGetAvailableVoices() async {
    final voicesStr = await methodChannel.invokeMethod<List<dynamic>>('ttsGetAvailableVoices');
    final voices =
        voicesStr
            ?.cast<String>()
            .map<Map<String, dynamic>>((str) => json.decode(str) as Map<String, dynamic>)
            .map<ReaderTTSVoice>((map) => ReaderTTSVoice.fromJson(map))
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
      methodChannel.invokeMethod('ttsSetPreferences', preferences.toJson());

  @override
  Future<void> audioEnable({AudioPreferences? prefs, Locator? fromLocator}) =>
      methodChannel.invokeMethod('audioEnable', [prefs?.toJson(), fromLocator?.toJson()]);

  @override
  Future<void> audioSetPreferences(AudioPreferences prefs) =>
      methodChannel.invokeMethod('audioSetPreferences', prefs.toJson());

  @override
  Future<void> audioSeekBy(Duration offset) => methodChannel.invokeMethod('audioSeekBy', offset.inSeconds);

  @override
  Future<List<TextSearchResult>> searchInPublication(String searchKey) async {
    final resultString = await methodChannel.invokeMethod<String>('searchInPublication', searchKey);

    if (resultString == null || resultString.isEmpty) {
      return <TextSearchResult>[];
    }

    try {
      final decoded = json.decode(resultString);
      if (decoded is List) {
        final collections = decoded
            .map((e) => LocatorCollection.fromJson(e as Map<String, dynamic>?))
            .whereType<LocatorCollection>()
            .toList();

        return _convertLocatorCollectionsToTextSearchResults(collections);
      }
      return <TextSearchResult>[];
    } catch (e) {
      throw Exception('Failed to parse search results: $e');
    }
  }

  List<TextSearchResult> _convertLocatorCollectionsToTextSearchResults(final List<LocatorCollection> collections) {
    final results = <TextSearchResult>[];

    for (final collection in collections) {
      for (final locator in collection.locators) {
        final result = TextSearchResult(
          locator: locator,
          chapterTitle: locator.title ?? collection.metadata.title ?? '',
          pageNumbers: null, // pageNumbers not currently available from Readium search
        );

        results.add(result);
      }
    }

    return results;
  }
}
