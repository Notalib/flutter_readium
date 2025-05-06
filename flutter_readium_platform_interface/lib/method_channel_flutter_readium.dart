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
  EventChannel locatorChannel = const EventChannel('dk.nota.flutter_readium/text-locator');

  /// The event channel used to receive text Locator changes from the native platform.
  @visibleForTesting
  EventChannel readerStatusChannel = const EventChannel('dk.nota.flutter_readium/reader-status');

  Stream<Locator>? _onTextLocatorChanged;

  /// Fires whenever the Reader's current Locator changes.
  // @override
  Stream<Locator> get onTextLocatorChanged {
    _onTextLocatorChanged ??= locatorChannel.receiveBroadcastStream().map((dynamic event) {
      Locator? newLocator = Locator.fromJson(json.decode(event) as Map<String, dynamic>);
      return newLocator;
    });
    return _onTextLocatorChanged!;
  }

  @override
  Future<Publication> openPublication(String pubUrl) async {
    String publicationString = await methodChannel
        .invokeMethod<String>('openPublication', [pubUrl]).then<String>((dynamic result) => result);
    return Publication.fromJson(json.decode(publicationString) as Map<String, dynamic>);
  }

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
}
