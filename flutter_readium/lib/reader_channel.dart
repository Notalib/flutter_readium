import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';

enum _ReaderChannelMethodInvoke {
  applyDecorations,
  go,
  goLeft,
  goRight,
  getCurrentLocator,
  getLocatorFragments,
  setLocation,
  isLocatorVisible,
  dispose,
  setPreferences,
}

/// Internal use only.
/// Used by ReadiumReaderWidget to talk to the native widget.
class ReadiumReaderChannel extends MethodChannel {
  ReadiumReaderChannel(super.name, {required this.onPageChanged, this.onExternalLinkActivated}) {
    setMethodCallHandler(onMethodCall);
  }

  final void Function(Locator) onPageChanged;
  void Function(String)? onExternalLinkActivated;

  /// Go e.g. navigate to a specific locator in the publication.
  Future<void> go(final Locator locator, {required final bool isAudioBookWithText, final bool animated = false}) {
    R2Log.d('$name: $locator, $animated');

    return _invokeMethod(_ReaderChannelMethodInvoke.go, [
      json.encode(locator.toTextLocator()),
      animated,
      isAudioBookWithText,
    ]);
  }

  /// Go to the previous page.
  Future<void> goLeft({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goLeft, animated);
  }

  /// Go to the next page.
  Future<void> goRight({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goRight, animated);
  }

  /// Get locator fragments for the given [locator].
  Future<Locator?> getLocatorFragments(final Locator locator) {
    R2Log.d('locator: ${locator.toString()}');

    return _invokeMethod(
      _ReaderChannelMethodInvoke.getLocatorFragments,
      json.encode(locator.toJson()),
    ).then((final value) => Locator.fromJson(json.decode(value))).onError((final error, final _) {
      R2Log.e(error ?? 'Unknown Error');

      throw ReadiumException('getLocatorFragments failed $locator');
    });
  }

  /// Set the current location to the given [locator].
  Future<void> setLocation(final Locator locator, final bool isAudioBookWithText) async =>
      _invokeMethod(_ReaderChannelMethodInvoke.setLocation, [json.encode(locator), isAudioBookWithText]);

  /// Set EPUB preferences.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    await _invokeMethod(_ReaderChannelMethodInvoke.setPreferences, preferences.toJson());
  }

  /// Apply decorations to the reader.
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    return await _invokeMethod(_ReaderChannelMethodInvoke.applyDecorations, [id, decorations.map((d) => d.toJson())]);
  }

  /// Get the current locator.
  Future<Locator?> getCurrentLocator() async => await _invokeMethod<dynamic>(
    _ReaderChannelMethodInvoke.getCurrentLocator,
    [],
  ).then((locStr) => locStr != null ? Locator.fromJson(json.decode(locStr) as Map<String, dynamic>) : null);

  /// Check if a locator is currently visible on screen.
  Future<bool> isLocatorVisible(final Locator locator) => _invokeMethod<bool>(
    _ReaderChannelMethodInvoke.isLocatorVisible,
    json.encode(locator),
  ).then((final isVisible) => isVisible!).onError((final error, final _) => true);

  Future<void> dispose() async {
    try {
      await _invokeMethod(_ReaderChannelMethodInvoke.dispose);
    } on Object catch (_) {
      // ignore
    }

    setMethodCallHandler(null);
  }

  /// Handles method calls from the native platform.
  Future<dynamic> onMethodCall(final MethodCall call) async {
    try {
      switch (call.method) {
        case 'onPageChanged':
          final args = call.arguments as String;
          final locatorJson = json.decode(args) as Map<String, dynamic>;
          final locator = Locator.fromJson(locatorJson);
          R2Log.d('onPageChanged $locator');
          onPageChanged(locator);

          return null;
        case 'onExternalLinkActivated':
          final link = call.arguments as String;
          R2Log.d('onExternalLinkActivated $link');
          onExternalLinkActivated?.call(link);

          return null;
        default:
          throw UnimplementedError('Unhandled call ${call.method}');
      }
    } on Object catch (e) {
      R2Log.e(e, data: call.method);
    }
  }

  /// Invokes a method on the native platform with optional arguments.
  Future<T?> _invokeMethod<T>(final _ReaderChannelMethodInvoke method, [final dynamic arguments]) {
    R2Log.d(() => arguments == null ? '$method' : '$method: $arguments');

    return invokeMethod<T>(method.name, arguments);
  }
}

/// Double-JSON-encodes `{'foo': 'bar', 'baz': 'quux'}` to
/// `'["{\"name\":\"foo\",\"value\":\"bar\"},{\"name\":\"baz\",\"value\":\"quux\"}]'`.
/// The original Readium UserProperty::getJson leaves out the quotes around "name" and "value".
/// There are plans to clean up the Readium user settings API.
/// TODO: Nuke this function from orbit if/when that happens.
String _readiumEncode(final Map<String, String> map) =>
    json.encode(map.entries.map((final e) => json.encode({'name': e.key, 'value': e.value})).toList());
