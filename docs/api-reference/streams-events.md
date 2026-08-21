# Streams & Events

`FlutterReadium` exposes four `Stream`s for real-time state updates.

## onTextLocatorChanged

Emits a `Locator` every time the visual reader position changes (page turn, scroll, navigation).

```dart
reader.onTextLocatorChanged.listen((locator) {
  final progress = locator.locations?.totalProgression ?? 0.0;
  final href = locator.href;
});
```

Debounce with `rxdart` when triggering expensive operations:

```dart
reader.onTextLocatorChanged
    .debounceTime(const Duration(seconds: 2))
    .listen((locator) => _save(locator));
```

## onTimebasedPlayerStateChanged

Emits a `ReadiumTimebasedState` during TTS and audio playback.

```dart
reader.onTimebasedPlayerStateChanged.listen((state) {
  final playing = state.state == TimebasedState.playing;
  final elapsed = state.currentOffset;          // Duration?
  final total = state.currentDuration;          // Duration?
  final publicationElapsed = state.totalProgressDuration; // Duration?
  final buffered = state.currentBuffered;       // Duration?
  final locator = state.currentLocator;         // Locator?
});
```

`TimebasedState` values: `playing`, `paused`, `loading`, `ended`, `failure`, `none`.

When `state == TimebasedState.failure` during TTS, `state.ttsErrorType` is non-null.

## onExternalPlaybackCommand

Emits a `ReadiumExternalPlaybackCommand` when playback controls are received from
system media controls, such as headphones, iOS Control Center, or the Android
media session / notification.

```dart
reader.onExternalPlaybackCommand.listen((command) {
  final action = command.action;     // ExternalPlaybackCommandAction
  final position = command.position; // Duration?
});
```

This stream reports user/system control intent. Use
`onTimebasedPlayerStateChanged` for the resulting playback state and progress.
The possible actions are `play`, `pause`, `togglePlayPause`, `seekForward`,
`seekBackward`, `seekTo`, `next`, `previous`, and `unknown`. For `seekTo`, `position` contains
the requested position relative to the configured `controlPanelTimebase`.

Android and iOS produce these events. The Web implementation exposes the stream
for API compatibility but does not currently emit events.

## onReaderStatusChanged

Emits `ReadiumReaderStatus` for reader lifecycle events.

```dart
reader.onReaderStatusChanged.listen((status) {
  switch (status) {
    case ReadiumReaderStatus.loading: showSpinner();
    case ReadiumReaderStatus.ready:   hideSpinner();
    case ReadiumReaderStatus.error:   showError();
    default: break;
  }
});
```

States: `loading`, `ready`, `closed`, `reachedEndOfPublication`, `error`.

`reachedEndOfPublication` is emitted on the Dart side only (not from native).

## onErrorEvent

Emits `ReadiumError` for non-fatal errors inside the reader.

```dart
reader.onErrorEvent.listen((error) {
  log('Reader error [${error.code}]: ${error.message}');
});
```

> **Android note:** The Android implementation does not currently emit errors automatically. Subscribe anyway for forward compatibility.

See [Error Codes](./error-codes.md) for the full `ReadiumErrorCode` vocabulary and severity/category classification.

## Best practices

- Always cancel subscriptions in `dispose()`:
  ```dart
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
  ```
- Use `.distinct()` to avoid reacting to duplicate consecutive values.
- Use `.debounceTime()` (rxdart) before expensive operations like database writes.
