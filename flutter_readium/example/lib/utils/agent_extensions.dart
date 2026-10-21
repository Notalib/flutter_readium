import 'dart:convert';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../state/index.dart';
import '../widgets/reader.widget.dart';
import 'navigator_key.dart';

// Debug-only VM service extensions that let agents drive steps that happen inside the native reader view.
// Call them through marionette's `call_custom_extension`, which prepends `ext.flutter.`. All args are strings.

const _prefix = 'ext.flutter.example';

void registerAgentExtensions() {
  _register('state', _state);
  _register('selectionAction', _selectionAction);
  _register('decorationTap', _decorationTap);
  _register('goToText', _goToText);
}

typedef _Handler = Future<Map<String, dynamic>> Function(Map<String, String> args);

void _register(String name, _Handler handler) {
  registerExtension('$_prefix.$name', (method, args) async {
    try {
      return ServiceExtensionResponse.result(jsonEncode(await handler(args)));
    } on ArgumentError catch (e) {
      return ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, '${e.message}');
    } on StateError catch (e) {
      return ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, e.message);
    } on Exception catch (e) {
      return ServiceExtensionResponse.error(ServiceExtensionResponse.extensionError, '$e');
    }
  });
}

/// A context under the bloc providers that also has a Navigator and Overlay, for sheets and dialogs.
BuildContext get _context {
  final context = navigatorKey.currentState?.overlay?.context;
  if (context == null) throw StateError('App is not ready');
  return context;
}

PublicationBloc _openPublicationBloc() {
  final bloc = _context.read<PublicationBloc>();
  if (bloc.state.publication == null) throw StateError('No publication is open');
  return bloc;
}

String _requireArg(Map<String, String> args, String name) {
  final value = args[name];
  if (value == null || value.isEmpty) throw ArgumentError('Missing argument: $name');
  return value;
}

/// Searches the open publication for `text` and returns the 1-based `occurrence`-th match's locator.
Future<Locator> _findText(Map<String, String> args) async {
  final text = _requireArg(args, 'text');
  final occurrence = int.tryParse(args['occurrence'] ?? '1') ?? 0;
  if (occurrence < 1) throw ArgumentError('occurrence must be a positive integer');
  _openPublicationBloc();
  final results = await FlutterReadium().searchInPublication(text);
  if (occurrence > results.length) {
    throw StateError('Found ${results.length} match(es) for "$text", wanted occurrence $occurrence');
  }
  return results[occurrence - 1].locator;
}

String? _hex(Color? color) =>
    color == null ? null : '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// `state` (no args) → `{publication, locator, highlights: [{id, text, tint, totalProgression}]}`.
/// Highlights are in reading order, tint is `#AARRGGBB`. `publication` and `locator` are null when unknown.
Future<Map<String, dynamic>> _state(Map<String, String> args) async {
  final context = _context;
  final state = context.read<PublicationBloc>().state;
  return {
    'publication': state.publication?.metadata.title,
    'locator': state.publication == null ? null : context.read<PublicationBloc>().currentLocator?.toJson(),
    'highlights': [
      for (final h in state.highlightsInReadingOrder)
        {
          'id': h.id,
          'text': h.text,
          'tint': _hex(h.tint),
          'totalProgression': h.decoration.locator.locations?.totalProgression,
        },
    ],
  };
}

/// `selectionAction` args `actionId` (`highlight`|`note`), `text`, optional `occurrence` (1-based, default 1).
/// Finds the text, then runs the selection-menu action on it as if chosen in the native menu.
/// Result: `{actionId, locator}`, plus `highlightId` for `highlight`.
Future<Map<String, dynamic>> _selectionAction(Map<String, String> args) async {
  final actionId = _requireArg(args, 'actionId');
  if (actionId != 'highlight' && actionId != 'note') throw ArgumentError('Unknown actionId: $actionId');
  final text = _requireArg(args, 'text');
  final locator = await _findText(args);
  final context = _context;
  if (!context.mounted) throw StateError('App is not ready');
  final event = SelectionActionEvent(
    actionId: actionId,
    locator: locator,
    selectedText: locator.text?.highlight ?? text,
  );

  final highlightId = handleSelectionAction(context, event);
  if (actionId == 'highlight' && highlightId == null) throw StateError('Highlight was not added');
  return {'actionId': actionId, 'locator': locator.toJson(), 'highlightId': ?highlightId};
}

/// `decorationTap` args `id`, optional `group` (default `user_highlights`).
/// Simulates a tap on a decoration. Result: `{opened}`, true when the highlight sheet was shown.
Future<Map<String, dynamic>> _decorationTap(Map<String, String> args) async {
  final id = _requireArg(args, 'id');
  final group = args['group'] ?? highlightsGroup;
  final highlight = _openPublicationBloc().state.highlights[id];
  final event = DecorationInteractionEvent(
    decorationId: id,
    group: group,
    type: DecorationInteractionType.tap,
    locator: highlight?.decoration.locator,
  );
  return {'opened': handleDecorationInteraction(_context, event)};
}

/// `goToText` args `text`, optional `occurrence` (1-based, default 1).
/// Navigates the reader to the match. Result: `{locator}` of the match.
Future<Map<String, dynamic>> _goToText(Map<String, String> args) async {
  final locator = await _findText(args);
  final context = _context;
  if (!context.mounted) throw StateError('App is not ready');
  context.read<PlayerControlsBloc>().add(GoToLocator(locator));
  return {'locator': locator.toJson()};
}
