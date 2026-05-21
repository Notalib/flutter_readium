# Error Handling

## Exception hierarchy

```
ReadiumException
├── OpeningReadiumException   — publication failed to open (has a typed cause)
├── PublicationNotSetReadiumException — operation before openPublication
└── OfflineReadiumException   — network content unavailable offline
```

## Catching errors on open

```dart
try {
  final pub = await reader.openPublication(url);
} on OpeningReadiumException catch (e) {
  switch (e.type) {
    case OpeningReadiumExceptionType.notFound:
      showError('File not found');
    case OpeningReadiumExceptionType.formatNotSupported:
      showError('Format not supported');
    case OpeningReadiumExceptionType.forbidden:
      showError('Access forbidden');
    default:
      showError('Cannot open: ${e.message}');
  }
} on ReadiumException catch (e) {
  showError(e.message);
}
```

## Error event stream

Non-fatal errors are emitted on `onErrorEvent`:

```dart
_errorSub = reader.onErrorEvent.listen((error) {
  // error.message, error.code, error.data
  log('Reader error ${error.code}: ${error.message}');
});
```

Always cancel this subscription in `dispose()`.

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

Dart-side logs are emitted through `R2Log`, which wraps [fimber](https://pub.dev/packages/fimber). Plant a tree to receive them:

```dart
Fimber.plantTree(DebugTree());
```

On the native side, logs go to the platform's standard log stream. Filter for the tag `flutter_readium`:

- **Android**: `adb logcat | grep flutter_readium` (or the Logcat filter in Android Studio).
- **iOS**: the Xcode console, or `xcrun simctl spawn booted log stream --predicate 'subsystem CONTAINS "flutter_readium"'`.

The native log level follows the Dart `setLogLevel` setting.

## Best practices

- Wrap `openPublication` in a try/catch — never assume a path is valid.
- Subscribe to `onErrorEvent` early and log or surface errors to users.
- Use `OpeningReadiumException.type` to give actionable messages rather than raw error strings.
- Always cancel stream subscriptions in `dispose()`.
