# Error Handling

## Awaited call failures

Awaited plugin calls throw `ReadiumException`, which wraps a `ReadiumError`.
Use `e.code` for the raw wire string and `e.codeEnum` for typed handling.

## Catching errors on open

```dart
try {
  final pub = await reader.openPublication(url);
} on ReadiumException catch (e) {
  switch (e.codeEnum) {
    case ReadiumErrorCode.notFound:
      showError('File not found');
    case ReadiumErrorCode.formatNotSupported:
      showError('Format not supported');
    case ReadiumErrorCode.forbidden:
      showError('Access forbidden');
    default:
      showError('Cannot open: ${e.message}');
  }
}
```

## Error event stream

Non-fatal errors are emitted on `onErrorEvent`:

```dart
_errorSub = reader.onErrorEvent.listen((error) {
  // error.message, error.code / error.codeEnum, error.details
  log('Reader error ${error.code}: ${error.message}');
});
```

Each `ReadiumError` carries a raw `code` string plus a typed `codeEnum`
(`ReadiumErrorCode`) with `category`, `isFatal` / `isInformational`, and a structured
`details` map (typed getters `href` / `attempt` / `maxAttempts` / `httpStatus`). See
[error-codes.md](../api-reference/error-codes.md) for the vocabulary. Audio-stream
failures during remote playback are recoverable and have their own flow — see
[audio-network-recovery.md](audio-network-recovery.md).

Always cancel this subscription in `dispose()`.

## Sentry

For awaited calls, capture the Dart callsite stack:

```dart
try {
  await reader.openPublication(url);
} on ReadiumException catch (e, st) {
  await Sentry.captureException(e, stackTrace: st);
}
```

For stream events, record the `ReadiumError` payload as context:

```dart
reader.onErrorEvent.listen((error) {
  Sentry.captureMessage(
    'Readium error event',
    withScope: (scope) {
      scope.setContexts('readiumError', error.toJson());
    },
  );
});
```

## Navigation errors

```dart
try {
  await reader.toPhysicalPageIndex('999', pub);
} on ReadiumException catch (e) {
  // 'Page link not found'
}

try {
  await reader.skipToNextTOC(publication: pub, currentTocHref: href);
} on ReadiumException catch (e) {
  // 'At the last chapter'
}
```

## Logging

The plugin exposes a log level that filters internal messages:

```dart
await reader.setLogLevel(LogLevel.debug);   // verbose
await reader.setLogLevel(LogLevel.warning); // quieter
```

Dart-side logs are emitted through `ReadiumLog`, which delegates to `logging` package

On the native side, logs go to the platform's standard log stream. Filter for the tag `flutter_readium`:

- **Android**: `adb logcat | grep flutter_readium` (or the Logcat filter in Android Studio).
- **iOS**: the Xcode console, or `xcrun simctl spawn booted log stream --predicate 'subsystem CONTAINS "flutter_readium"'`.

The native log level follows the Dart `setLogLevel` setting.

## Best practices

- Wrap `openPublication` in a try/catch — never assume a path is valid.
- Subscribe to `onErrorEvent` early and log or surface errors to users.
- Use `ReadiumException.codeEnum` / `ReadiumError.codeEnum` to give actionable messages rather than raw strings.
- Always cancel stream subscriptions in `dispose()`.
