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
/// the level at runtime — this also propagates to the native (iOS/Android) and
/// web (JS bundle) sides.
///
/// For tagged logging, create a [TaggedReadiumLog] instance:
/// ```dart
/// static final _log = ReadiumLog.tag('WebPlugin');
/// _log.info('Publication opened'); // → INFO  [flutter_readium/WebPlugin] Publication opened
/// ```
///
/// Log records are formatted as `LEVEL [loggerName] message` where the logger
/// name uses `/` to separate namespace from tag. Use [ReadiumLog.format] in
/// your `Logger.root.onRecord` listener to produce this convention:
/// ```dart
/// Logger.root.onRecord.listen((r) => debugPrint(ReadiumLog.format(r)));
/// ```
abstract class ReadiumLog {
  const ReadiumLog._();

  // Custom Level constants with names matching our LogLevel enum and the web
  // logger convention. Values are kept identical to the standard package:logging
  // levels so filter thresholds (`logger.level = ...`) remain consistent with
  // the rest of the logging tree.
  //
  // LogLevel index alignment (used for the Dart → native/web bridge):
  //   LogLevel.none  = 0  →  Level.OFF   (1200)
  //   LogLevel.error = 1  →  _levelError (1000)
  //   LogLevel.warn  = 2  →  _levelWarn  (900)
  //   LogLevel.info  = 3  →  Level.INFO  (800)
  //   LogLevel.debug = 4  →  _levelDebug (500)
  // The TypeScript LogLevel enum in logger.ts uses the same numeric values
  // so that `level.index.toJS` passes correctly across the bridge.
  static const Level _levelDebug = Level('DEBUG', 500);
  static const Level _levelWarn = Level('WARN', 900);
  static const Level _levelError = Level('ERROR', 1000);

  static final Logger _logger = Logger('flutter_readium');

  /// Creates a tagged logger that uses a child [Logger] named
  /// `flutter_readium.<tag>`. This surfaces the tag/source in log records so
  /// consumers can filter by area (e.g. Navigator, TTS, WebPlugin).
  static TaggedReadiumLog tag(final String tag) => TaggedReadiumLog._(tag);

  /// Formats a [LogRecord] using the plugin's log convention:
  /// `LEVEL [flutter_readium/Tag] message`
  ///
  /// The level name is left-padded to 5 characters so log lines align
  /// vertically, making it easy to scan a stream for `WARN`/`ERROR` entries.
  ///
  /// Use this in your `Logger.root.onRecord` listener:
  /// ```dart
  /// Logger.root.onRecord.listen((r) => debugPrint(ReadiumLog.format(r)));
  /// ```
  ///
  /// Examples:
  /// ```
  /// INFO  [flutter_readium] Received reader status event: ready
  /// WARN  [flutter_readium/WebPlugin] setCustomHeaders not supported on web
  /// DEBUG [flutter_readium/TTS] play (with locator)
  /// ERROR [flutter_readium/Reader] Failed to open publication: HTTP 404
  /// ```
  static String format(final LogRecord record) {
    // flutter_readium.WebPlugin → flutter_readium/WebPlugin
    final name = record.loggerName.replaceFirst('.', '/');
    final level = record.level.name.padRight(5);
    final msg = record.message;
    if (record.error != null) {
      return '$level [$name] $msg (${record.error})';
    }
    return '$level [$name] $msg';
  }

  /// Map a [LogLevel] to a `package:logging` [Level] and apply it.
  static void setLevel(final LogLevel level) {
    hierarchicalLoggingEnabled = true;
    _logger.level = _toLoggingLevel(level);
  }

  static Level _toLoggingLevel(final LogLevel level) => switch (level) {
    LogLevel.none => Level.OFF,
    LogLevel.error => _levelError,
    LogLevel.warn => _levelWarn,
    LogLevel.info => Level.INFO,
    LogLevel.debug => _levelDebug,
  };

  // ---------------------------------------------------------------------------
  // Full-name API (preferred for new code — mirrors the web logger convention)
  // ---------------------------------------------------------------------------

  /// Debug-level — only emitted in [kDebugMode]. Accepts a value or a
  /// zero-argument function (evaluated lazily, only when the message will
  /// actually be emitted).
  static void debug(final dynamic message) {
    if (kDebugMode) {
      _logger.log(_levelDebug, message is Function ? message() : message.toString());
    }
  }

  static void info(final String? message) => _logger.info(message ?? '');

  static void warn(final String? message) => _logger.log(_levelWarn, message ?? '');

  /// Log an error. [error] can be any object; pass [stackTrace] when available.
  static void error(final Object err, {final Object? data, final StackTrace? stackTrace}) {
    final msg = data != null ? '$err $data' : err.toString();
    _logger.log(_levelError, msg, err, stackTrace);
  }

  // ---------------------------------------------------------------------------
  // Short-name aliases (kept for backward compatibility)
  // ---------------------------------------------------------------------------

  /// Alias for [debug].
  static void d(final dynamic message) => debug(message);

  /// Alias for [info].
  static void i(final String? message) => info(message);

  /// Alias for [warn].
  static void w(final String? message) => warn(message);

  /// Alias for [error].
  static void e(final Object err, {final Object? data, final StackTrace? stackTrace}) =>
      error(err, data: data, stackTrace: stackTrace);
}

/// A tagged variant of [ReadiumLog] that routes logs through a child logger
/// named `flutter_readium.<tag>`. The tag appears in the `loggerName` field of
/// [LogRecord], making it easy to identify the source of a log message.
///
/// Obtain an instance via [ReadiumLog.tag]:
/// ```dart
/// static final _log = ReadiumLog.tag('Navigator');
/// ```
///
/// With [ReadiumLog.format], output looks like:
/// ```
/// DEBUG [flutter_readium/Navigator] goForward
/// INFO  [flutter_readium/TTS] play (with locator)
/// ```
class TaggedReadiumLog {
  TaggedReadiumLog._(final String tag) : _logger = Logger('flutter_readium.$tag');

  final Logger _logger;

  // ---------------------------------------------------------------------------
  // Full-name API (mirrors the web logger convention)
  // ---------------------------------------------------------------------------

  /// Debug-level — only emitted in [kDebugMode]. Accepts a value or a
  /// zero-argument function (evaluated lazily).
  void debug(final dynamic message) {
    if (kDebugMode) {
      _logger.log(ReadiumLog._levelDebug, message is Function ? message() : message.toString());
    }
  }

  void info(final String? message) => _logger.info(message ?? '');

  void warn(final String? message) => _logger.log(ReadiumLog._levelWarn, message ?? '');

  /// Log an error. [error] can be any object; pass [stackTrace] when available.
  void error(final Object err, {final Object? data, final StackTrace? stackTrace}) {
    final msg = data != null ? '$err $data' : err.toString();
    _logger.log(ReadiumLog._levelError, msg, err, stackTrace);
  }

  // ---------------------------------------------------------------------------
  // Short-name aliases (kept for backward compatibility)
  // ---------------------------------------------------------------------------

  /// Alias for [debug].
  void d(final dynamic message) => debug(message);

  /// Alias for [info].
  void i(final String? message) => info(message);

  /// Alias for [warn].
  void w(final String? message) => warn(message);

  /// Alias for [error].
  void e(final Object err, {final Object? data, final StackTrace? stackTrace}) =>
      error(err, data: data, stackTrace: stackTrace);
}
