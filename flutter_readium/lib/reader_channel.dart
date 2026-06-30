import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'flutter_readium.dart';

enum _ReaderChannelMethodInvoke {
  applyDecorations,
  configureSelectionActions,
  go,
  goBackward,
  goForward,
  notifyUserNavigation,
  dispose,
  setPreferences,
}

/// Internal use only.
/// Used by ReadiumReaderWidget to talk to the native widget.
class ReadiumReaderChannel extends MethodChannel {
  /// Creates a channel bound to [name]. [onPageChanged] is called when the
  /// native navigator reports a page change. [onExternalLinkActivated] is
  /// called when an external (non-publication) link is tapped.
  ReadiumReaderChannel(
    super.name, {
    required this.onPageChanged,
    this.onExternalLinkActivated,
    this.onTextSelected,
    this.onSelectionAction,
    this.onDecorationInteraction,
    this.onImageTapped,
  }) {
    setMethodCallHandler(onMethodCall);
  }

  static final _log = ReadiumLog.tag('ReaderChannel');

  /// Called by the native side whenever the visible page changes.
  final void Function(Locator) onPageChanged;

  /// Called when the reader activates a link that points outside the publication.
  void Function(String)? onExternalLinkActivated;

  /// Called when the user selects text in the reader.
  void Function(TextSelectionEvent)? onTextSelected;

  /// Called when the user taps a configured editing action on selected text.
  void Function(SelectionActionEvent)? onSelectionAction;

  /// Called when the user interacts with an existing decoration.
  void Function(DecorationInteractionEvent)? onDecorationInteraction;

  /// Called when the user taps an image in the EPUB.
  void Function(ImageTapEvent)? onImageTapped;

  /// Go e.g. navigate to a specific locator in the publication.
  Future<void> go(
    final Locator locator, {
    required final bool isAudioBookWithText,
    final bool animated = false,
  }) {
    _log.d('$name: $locator, $animated');

    return _invokeMethod(_ReaderChannelMethodInvoke.go, [
      json.encode(locator.toTextLocator()),
      animated,
      isAudioBookWithText,
    ]);
  }

  /// Go to the previous page.
  Future<void> goBackward({final bool animated = true}) {
    _log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goBackward, animated);
  }

  /// Go to the next page.
  Future<void> goForward({final bool animated = true}) {
    _log.d('$name: $animated');
    return _invokeMethod(_ReaderChannelMethodInvoke.goForward, animated);
  }

  /// Signals that the user manually interacted with the reader (a swipe or
  /// edge-tap page navigation). The native side enters narration "manual mode"
  /// if narration is currently driving the reader; otherwise it is a no-op.
  Future<void> notifyUserNavigation() {
    _log.d(name);
    return _invokeMethod(_ReaderChannelMethodInvoke.notifyUserNavigation);
  }

  /// Set EPUB preferences.
  Future<void> setEPUBPreferences(EPUBPreferences preferences) async {
    await _invokeMethod(
      _ReaderChannelMethodInvoke.setPreferences,
      preferences.toJson(),
    );
  }

  /// Set PDF preferences.
  Future<void> setPDFPreferences(PDFPreferences preferences) async {
    await _invokeMethod(
      _ReaderChannelMethodInvoke.setPreferences,
      preferences.toJson(),
    );
  }

  /// Apply decorations to the reader.
  Future<void> applyDecorations(
    String id,
    List<ReaderDecoration> decorations,
  ) async => await _invokeMethod(_ReaderChannelMethodInvoke.applyDecorations, [
    id,
    decorations.map((d) => json.encode(d.toJson())).toList(),
  ]);

  /// Configure the native selection context menu actions.
  Future<void> configureSelectionActions(List<SelectionAction> actions) async => await _invokeMethod(
    _ReaderChannelMethodInvoke.configureSelectionActions,
    actions.map((a) => a.toJson()).toList(),
  );

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
          _log.d('onPageChanged $locator');

          if (locator == null) {
            _log.w('onPageChanged received empty locator');
            return null;
          }

          onPageChanged(locator);

          return null;
        case 'onExternalLinkActivated':
          final link = call.arguments as String;
          _log.d('onExternalLinkActivated $link');
          onExternalLinkActivated?.call(link);

          return null;
        case 'onTextSelected':
          final args = call.arguments as String;
          final eventJson = json.decode(args) as Map<String, dynamic>;
          final event = TextSelectionEvent.fromJson(eventJson);
          _log.d('onTextSelected ${event.selectedText}');
          onTextSelected?.call(event);

          return null;
        case 'onSelectionAction':
          final args = call.arguments as String;
          final eventJson = json.decode(args) as Map<String, dynamic>;
          final event = SelectionActionEvent.fromJson(eventJson);
          _log.d('onSelectionAction ${event.actionId}');
          onSelectionAction?.call(event);

          return null;
        case 'onDecorationInteraction':
          final args = call.arguments as String;
          final eventJson = json.decode(args) as Map<String, dynamic>;
          final event = DecorationInteractionEvent.fromJson(eventJson);
          _log.d('onDecorationInteraction ${event.decorationId}');
          onDecorationInteraction?.call(event);

          return null;
        case 'onImageTapped':
          final args = call.arguments as String;
          final eventJson = json.decode(args) as Map<String, dynamic>;
          final event = ImageTapEvent.fromJson(eventJson);
          _log.d('onImageTapped ${event.href}');
          onImageTapped?.call(event);

          return null;
        default:
          throw UnimplementedError('Unhandled call ${call.method}');
      }
    } on Object catch (e, st) {
      _log.e(e, data: call.method, stackTrace: st);
    }
  }

  /// Invokes a method on the native platform with optional arguments.
  Future<T?> _invokeMethod<T>(
    final _ReaderChannelMethodInvoke method, [
    final dynamic arguments,
  ]) {
    _log.d(() => arguments == null ? '$method' : '$method: $arguments');

    return invokeMethod<T>(method.name, arguments);
  }
}
