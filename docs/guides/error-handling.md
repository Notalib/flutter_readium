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

## Crash and error reporting

For awaited calls, report the thrown `ReadiumException` with the Dart callsite
stack from the `catch` block. This stack is usually the most useful application
context: it shows where the client app called the plugin.

```dart
try {
  await reader.openPublication(url);
} on ReadiumException catch (e, st) {
  await crashReporter.captureException(e, stackTrace: st);
}
```

For stream events, no exception is thrown. Record terminal/fatal events as a
message or synthetic exception, and attach `error.toJson()` as structured
context.

```dart
reader.onErrorEvent.listen((error) {
  if (error.isFatal) {
    crashReporter.captureMessage(
      'Readium error event',
      context: {'readiumError': error.toJson()},
    );
  }
});
```

Native crashes are handled by the client application's normal iOS/Android crash
reporting setup. Make sure native symbols are uploaded according to your crash
reporting provider's instructions.

Handled native failures, such as a failed HTTP request while streaming remote
audio, are not native crashes. The plugin converts them into `ReadiumException`
or `ReadiumError` values. Native stack traces stay in the platform logs; the
wire payload carries stable diagnostic fields such as `code`, `href`,
`httpStatus`, `attempt`, `maxAttempts`, and `message`.

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
