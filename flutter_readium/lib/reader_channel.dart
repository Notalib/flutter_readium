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
  isReaderReady,
  dispose,
  setPreferences,
  ttsStart,
  ttsStop,
}

/// Internal use only.
/// Used by ReadiumReaderWidget to talk to the native widget.
class ReadiumReaderChannel extends MethodChannel {
  ReadiumReaderChannel(
    super.name, {
    required this.onPageChanged,
  }) {
    setMethodCallHandler(onMethodCall);
  }

  final void Function(Locator) onPageChanged;

  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) {
    R2Log.d('$name: $locator, $animated');

    return _invokeMethod(
      _ReaderChannelMethodInvoke.go,
      [
        json.encode(locator.toTextLocator()),
        animated,
        isAudioBookWithText,
      ],
    );
  }

  Future<void> goLeft({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(
      _ReaderChannelMethodInvoke.goLeft,
      animated,
    );
  }

  Future<void> goRight({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(
      _ReaderChannelMethodInvoke.goRight,
      animated,
    );
  }

  Future<Locator?> getLocatorFragments(final Locator locator) {
    R2Log.d('locator: ${locator.toString()}');

    return _invokeMethod(
      _ReaderChannelMethodInvoke.getLocatorFragments,
      json.encode(locator.toJson()),
    )
        .then((final value) => Locator.fromJson(json.decode(value)))
        .onError((final error, final _) {
      R2Log.e(error ?? 'Unknown Error');

      throw ReadiumException('getLocatorFragments failed $locator');
    });
  }

  Future<void> setLocation(
          final Locator locator, final bool isAudioBookWithText) async =>
      _invokeMethod(
        _ReaderChannelMethodInvoke.setLocation,
        [
          json.encode(locator),
          isAudioBookWithText,
        ],
      );

  Future<void> ttsStart(final String lang, final Locator? fromLocator) async =>
      _invokeMethod(
        _ReaderChannelMethodInvoke.ttsStart,
        [
          lang,
          fromLocator?.toJson(),
        ],
      );

  Future<void> ttsStop() async =>
      _invokeMethod(_ReaderChannelMethodInvoke.ttsStop, []);

  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    await _invokeMethod(
        _ReaderChannelMethodInvoke.setPreferences, preferences.toJson());
  }

  Future<void> applyDecorations(
      String id, List<ReaderDecoration> decorations) async {
    return await _invokeMethod(_ReaderChannelMethodInvoke.applyDecorations,
        [id, decorations.map((d) => d.toJson())]);
  }

  Future<bool> isReaderReady() async => _invokeMethod(
        _ReaderChannelMethodInvoke.isReaderReady,
      ).timeout(const Duration(seconds: 5)).then((final value) {
        if (value is bool) {
          return value;
        }

        return bool.tryParse(value) ?? false;
      }).onError(
        (final error, final _) {
          R2Log.d(error.toString());

          return false;
        },
      );

  Future<Locator?> getCurrentLocator() async => await _invokeMethod<dynamic>(
          _ReaderChannelMethodInvoke.getCurrentLocator, [])
      .then((locStr) => locStr != null
          ? Locator.fromJson(json.decode(locStr) as Map<String, dynamic>)
          : null);

  Future<bool> isLocatorVisible(final Locator locator) => _invokeMethod<bool>(
        _ReaderChannelMethodInvoke.isLocatorVisible,
        json.encode(locator),
      )
          .then((final isVisible) => isVisible!)
          .onError((final error, final _) => true);

  Future<void> dispose() async {
    try {
      await _invokeMethod(_ReaderChannelMethodInvoke.dispose);
    } on Object catch (_) {
      // ignore
    }

    setMethodCallHandler(null);
  }

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
          // TODO: Handle external link activations?

          return null;
        default:
          throw UnimplementedError('Unhandled call ${call.method}');
      }
    } on Object catch (e) {
      R2Log.e(e, data: call.method);
    }
  }

  Future<T?> _invokeMethod<T>(final _ReaderChannelMethodInvoke method,
      [final dynamic arguments]) {
    R2Log.d(() => arguments == null ? '$method' : '$method: $arguments');

    return invokeMethod<T>(method.name, arguments);
  }
}

/// Double-JSON-encodes `{'foo': 'bar', 'baz': 'quux'}` to
/// `'["{\"name\":\"foo\",\"value\":\"bar\"},{\"name\":\"baz\",\"value\":\"quux\"}]'`.
/// The original Readium UserProperty::getJson leaves out the quotes around "name" and "value".
/// There are plans to clean up the Readium user settings API.
/// TODO: Nuke this function from orbit if/when that happens.
String _readiumEncode(final Map<String, String> map) => json.encode(map.entries
    .map((final e) => json.encode({'name': e.key, 'value': e.value}))
    .toList());
