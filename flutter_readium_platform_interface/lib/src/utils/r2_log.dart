import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:json_diff/json_diff.dart';

import '../_index.dart';

final _deviceStackTraceRegex = RegExp(r'#[0-9]+[\s]+(.+) \(([^\s]+)\)');
final _webStackTraceRegex = RegExp(r'^((packages|dart-sdk)\/[^\s]+\/)');
final _browserStackTraceRegex = RegExp(r'^(?:package:)?(dart:[^\s]+|[^\s]+)');
const _stackTraceBeginIndex = 2;
const _methodCount = 1;

// Trace logs in Flutter readium.
// Add keywords as class name or method name.
const _trace = <String>[
  // EX. FlutterReadium
  '',
];

abstract class R2Log {
  const R2Log._();

  static void d(
    final dynamic message, {
    final int? wrapWidth,
    final int? stackTraceBeginIndex,
  }) {
    if (kDebugMode) {
      final log = _log(message, stackTraceBeginIndex: stackTraceBeginIndex);
      final caseInsensitiveLog = log.toLowerCase();

      if (_trace.any((final trace) => caseInsensitiveLog.contains(trace.toLowerCase()))) {
        // debugPrintSynchronously(log, wrapWidth: wrapWidth);
        debugPrintThrottled(log, wrapWidth: wrapWidth);
      }
    }
  }

  static void i(final String? message, {final int? wrapWidth}) => debugPrint(
        'INFO: $message',
        wrapWidth: wrapWidth,
      );

  static void w(final String? message, {final int? wrapWidth}) => debugPrint(
        'WARNING: $message',
        wrapWidth: wrapWidth,
      );

  static void e(
    final Object error, {
    final int? wrapWidth,
    final Object? data,
  }) {
    late ReadiumError err;

    if (error is ReadiumError) {
      err = error;
    } else if (error is PlatformException) {
      err = ReadiumError(
        error.message.toString(),
        code: error.code,
        data: data,
      );
    } else {
      err = ReadiumError(
        error.toString(),
        data: data,
      );
    }

    debugPrint(
      _log('ERROR: $error ${data ?? ''}'),
      wrapWidth: wrapWidth,
    );
  }

  static void logMapDiff(
    final Map? leftJson,
    final Map? rightJson, {
    final String? prefix,
    final int? wrapWidth,
    final int? stackTraceBeginIndex,
  }) {
    R2Log.d(
      _logDiff(
        leftJson: leftJson,
        rightJson: rightJson,
        prefix: prefix,
      ),
      stackTraceBeginIndex: stackTraceBeginIndex,
    );
  }
}

String _logMapDiffPrefix(
  final String message, {
  final int indent = 0,
  final String? prefix,
}) =>
    '\n${prefix ?? ''}${'\t' * indent} $message';

String _logDiff({
  final Map? leftJson,
  final Map? rightJson,
  final DiffNode? diffNode,
  final int indent = 1,
  final String? prefix,
}) {
  final diff = diffNode ?? JsonDiffer.fromJson(leftJson ?? {}, rightJson ?? {}).diff();

  if (diff.hasNothing) {
    return _logMapDiffPrefix(
      'No diff',
      indent: 0,
      prefix: prefix,
    );
  }

  final all = {
    ...diff.added.map((final key, final value) => MapEntry(key, [null, value])),
    ...diff.changed,
    ...diff.removed.map((final key, final value) => MapEntry(key, [value, null])),
    ...diff.node,
  };

  var message = '';
  for (final entry in all.entries) {
    final key = entry.key;
    final value = entry.value;

    if (value is List) {
      final left = value.first;
      final right = value.last;

      if (left is Map || right is Map) {
        message += _logMapDiffPrefix(
          '$key:',
          prefix: prefix,
          indent: indent,
        );
        message += _logDiff(
          leftJson: left,
          rightJson: right,
          indent: indent + 1,
          prefix: prefix,
        );
      } else {
        message += _logMapDiffPrefix(
          '$key: $left --> $right',
          prefix: prefix,
          indent: indent,
        );
      }
    } else if (value is DiffNode) {
      message += _logMapDiffPrefix(
        '$key:',
        prefix: prefix,
        indent: indent,
      );
      message += _logDiff(
        diffNode: value,
        prefix: prefix,
        indent: indent + 1,
      );
    } else {
      message += _logMapDiffPrefix(
        '$key: ${leftJson == null ? 'null' : value} --> ${rightJson == null ? 'null' : value}',
        prefix: prefix,
        indent: indent,
      );
    }
  }

  return message;
}

String _log(final dynamic message, {final int? stackTraceBeginIndex}) {
  final messageStr = _stringifyMessage(message);

  final stackTraceStr = _formatStackTrace(
    StackTrace.current,
    stackTraceBeginIndex: stackTraceBeginIndex,
  );

  return _formatAndPrint(
    messageStr,
    stackTraceStr,
  );
}

String _formatStackTrace(final StackTrace stackTrace, {final int? stackTraceBeginIndex}) {
  var lines = stackTrace.toString().split('\n');
  if (_stackTraceBeginIndex > 0 && _stackTraceBeginIndex < lines.length - 1) {
    lines = lines.sublist(_stackTraceBeginIndex + (stackTraceBeginIndex ?? 0));
  }
  final formatted = <String>[];
  var count = 0;
  for (final line in lines) {
    if (_discardDeviceStacktraceLine(line) ||
        _discardWebStacktraceLine(line) ||
        _discardBrowserStacktraceLine(line) ||
        line.isEmpty) {
      continue;
    }
    formatted.add(line.replaceFirst(RegExp(r'#\d+\s+'), ''));
    if (++count == _methodCount) {
      break;
    }
  }

  return formatted.join('\n');
}

bool _discardDeviceStacktraceLine(final String line) {
  final match = _deviceStackTraceRegex.matchAsPrefix(line);
  if (match == null) {
    return false;
  }
  return match.group(2)!.startsWith('package:logger');
}

bool _discardWebStacktraceLine(final String line) {
  final match = _webStackTraceRegex.matchAsPrefix(line);
  if (match == null) {
    return false;
  }
  return match.group(1)!.startsWith('packages/logger') || match.group(1)!.startsWith('dart-sdk/lib');
}

bool _discardBrowserStacktraceLine(final String line) {
  final match = _browserStackTraceRegex.matchAsPrefix(line);
  if (match == null) {
    return false;
  }
  return match.group(1)!.startsWith('package:logger') || match.group(1)!.startsWith('dart:');
}

// Handles any object that is causing JsonEncoder() problems
Object _toEncodableFallback(final dynamic object) => object.toString();

String _stringifyMessage(final dynamic message) {
  final msg = message is Function ? message.call() : message;
  if (msg is Map || msg is Iterable) {
    const encoder = JsonEncoder.withIndent('  ', _toEncodableFallback);
    return encoder.convert(msg);
  } else {
    return msg.toString();
  }
}

String _formatAndPrint(
  final String message,
  final String stacktrace,
) {
  final stackTraceSplit = stacktrace.replaceAll('.<anonymous closure>', '').split(' ');

  return '[[ ${stackTraceSplit.first} ]] $message ${stackTraceSplit.last}';
}
