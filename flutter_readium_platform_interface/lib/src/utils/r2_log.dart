import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../index.dart';

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

  static void d(final dynamic message, {final int? wrapWidth, final int? stackTraceBeginIndex}) {
    if (kDebugMode) {
      final log = _log(message, stackTraceBeginIndex: stackTraceBeginIndex);
      final caseInsensitiveLog = log.toLowerCase();

      if (_trace.any((final trace) => caseInsensitiveLog.contains(trace.toLowerCase()))) {
        // debugPrintSynchronously(log, wrapWidth: wrapWidth);
        debugPrintThrottled(log, wrapWidth: wrapWidth);
      }
    }
  }

  static void i(final String? message, {final int? wrapWidth}) => debugPrint('INFO: $message', wrapWidth: wrapWidth);

  static void w(final String? message, {final int? wrapWidth}) => debugPrint('WARNING: $message', wrapWidth: wrapWidth);

  static void e(final Object error, {final int? wrapWidth, final Object? data}) {
    late ReadiumError err;

    if (error is ReadiumError) {
      err = error;
    } else if (error is PlatformException) {
      err = ReadiumError(error.message.toString(), code: error.code, data: data);
    } else {
      err = ReadiumError(error.toString(), data: data);
    }

    debugPrint(_log('ERROR: $err ${data ?? ''}'), wrapWidth: wrapWidth);
  }
}

String _log(final dynamic message, {final int? stackTraceBeginIndex}) {
  final messageStr = _stringifyMessage(message);

  final stackTraceStr = _formatStackTrace(StackTrace.current, stackTraceBeginIndex: stackTraceBeginIndex);

  return _formatAndPrint(messageStr, stackTraceStr);
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

String _formatAndPrint(final String message, final String stacktrace) {
  final stackTraceSplit = stacktrace.replaceAll('.<anonymous closure>', '').split(' ');

  return '[[ ${stackTraceSplit.first} ]] $message ${stackTraceSplit.last}';
}
