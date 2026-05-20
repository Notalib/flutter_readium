import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../exceptions/log_level.dart';

/// Plugin-wide logger backed by `package:logging`.
///
/// Output is routed through whatever `Logger.root.onRecord` listener the host
/// app sets up — no listener means no output.  The example app already
/// configures one in `main.dart`.
///
/// The logger is named `'flutter_readium'` so host apps can control it
/// independently:
///
/// ```dart
/// Logger('flutter_readium').level = Level.WARNING;
/// ```
///
/// Call [ReadiumLog.setLevel] (or `FlutterReadium().setLogLevel(...)`) to change
/// the level at runtime — this also propagates to the native (iOS/Android)
/// side.
abstract class ReadiumLog {
  const ReadiumLog._();

  static final Logger _logger = Logger('flutter_readium');

  /// Map a [LogLevel] to a `package:logging` [Level] and apply it.
  static void setLevel(final LogLevel level) {
    hierarchicalLoggingEnabled = true;
    _logger.level = _toLoggingLevel(level);
  }

  static Level _toLoggingLevel(final LogLevel level) => switch (level) {
    LogLevel.none => Level.OFF,
    LogLevel.error => Level.SEVERE,
    LogLevel.warn => Level.WARNING,
    LogLevel.info => Level.INFO,
    LogLevel.debug => Level.FINE,
  };

  /// Debug-level — only emitted in [kDebugMode].
  static void d(final dynamic message) {
    if (kDebugMode) {
      _logger.fine(message is Function ? message() : message.toString());
    }
  }

  static void i(final String? message) => _logger.info(message ?? '');

  static void w(final String? message) => _logger.warning(message ?? '');

  /// Log an error. [error] can be any object; pass [stackTrace] when available.
  static void e(final Object error, {final Object? data, final StackTrace? stackTrace}) {
    final msg = data != null ? '$error $data' : error.toString();
    _logger.severe(msg, error, stackTrace);
  }
}
