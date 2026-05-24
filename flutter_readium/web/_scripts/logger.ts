/**
 * Lightweight tagged logger for the Readium web bundle.
 *
 * All messages are prefixed with the padded level and `[Readium/<tag>]` so
 * they align vertically and can be easily filtered in the browser DevTools
 * console:
 *
 *   DEBUG [Readium/Reader] goForward
 *   INFO  [Readium/WebPlugin] publication opened
 *   WARN  [Readium/TTS] voice not found, using default
 *   ERROR [Readium/Reader] failed to open publication
 *
 * The active level can be changed at runtime via `setLogLevel()` which is
 * exposed on the ReadiumReader class so the Dart side can control verbosity
 * through the plugin's `setLogLevel` interface method.
 */

/**
 * Log verbosity levels.
 *
 * Values are intentionally identical to the indices of Dart's `LogLevel` enum:
 *   none=0, error=1, warn=2, info=3, debug=4
 *
 * This means the Dart bridge can pass `level.index` directly as a number and
 * this enum interprets it correctly — no translation layer needed.
 * Do NOT reorder or insert values.
 */
export enum LogLevel {
  none = 0,
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
}

let _currentLevel: LogLevel = LogLevel.info;

/** Sets the minimum log level. Messages below this level are suppressed. */
export function setLogLevel(level: LogLevel): void {
  _currentLevel = level;
}

/** Returns the current active log level. */
export function getLogLevel(): LogLevel {
  return _currentLevel;
}

export interface Logger {
  debug(...args: unknown[]): void;
  info(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
}

export function createLogger(tag: string): Logger {
  const prefix = `[Readium/${tag}]`;
  return {
    debug: (...args) => {
      if (_currentLevel >= LogLevel.debug) console.debug("DEBUG", prefix, ...args);
    },
    info: (...args) => {
      if (_currentLevel >= LogLevel.info) console.info("INFO ", prefix, ...args);
    },
    warn: (...args) => {
      if (_currentLevel >= LogLevel.warn) console.warn("WARN ", prefix, ...args);
    },
    error: (...args) => {
      if (_currentLevel >= LogLevel.error) console.error("ERROR", prefix, ...args);
    },
  };
}
