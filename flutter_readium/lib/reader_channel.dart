import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';

enum _ReaderChannelMethodInvoke { applyDecorations, go, goBackward, goForward, dispose, setPreferences }

/// Internal use only.
/// Used by ReadiumReaderWidget to talk to the native widget.
class ReadiumReaderChannel extends MethodChannel {
  /// Creates a channel bound to [name]. [onPageChanged] is called when the
  /// native navigator reports a page change. [onExternalLinkActivated] is
  /// called when an external (non-publication) link is tapped.
  ReadiumReaderChannel(super.name, {required this.onPageChanged, this.onExternalLinkActivated}) {
    setMethodCallHandler(onMethodCall);
  }

  /// Called by the native side whenever the visible page changes.
  final void Function(Locator) onPageChanged;

  /// Called when the reader activates a link that points outside the publication.
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
  Future<void> goBackward({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goBackward, animated);
  }

  /// Go to the next page.
  Future<void> goForward({final bool animated = true}) {
    R2Log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goForward, animated);
  }

  /// Set EPUB preferences.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    await _invokeMethod(_ReaderChannelMethodInvoke.setPreferences, preferences.toJson());
  }

  /// Apply decorations to the reader.
  Future<void> applyDecorations(String id, List<ReaderDecoration> decorations) async {
    return await _invokeMethod(_ReaderChannelMethodInvoke.applyDecorations, [id, decorations.map((d) => d.toJson())]);
  }

  /// Tears down the method channel handler and signals the native side to clean up.
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

          if (locator == null) {
            R2Log.w('onPageChanged received empty locator');
            return null;
          }

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
