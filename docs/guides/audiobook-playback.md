# Audiobook Playback

Covers pre-recorded audio publications and MediaOverlay (synchronised narration) books.

## Detecting publication type

```dart
if (pub.conformsToReadiumAudiobook) {
  // Pure audiobook — no visual reader widget needed
} else if (pub.containsMediaOverlays) {
  // EPUB/WebPub with synchronised audio narration
}
```

## Enabling audio

```dart
await reader.audioEnable(
  prefs: AudioPreferences(
    speed: 1.0,
    seekInterval: 30,
    allowExternalSeeking: true, // lock screen controls
  ),
  fromLocator: _savedLocator,   // null = from the beginning
);
```

## Playback controls

```dart
await reader.play(null);           // start from current position
await reader.play(someLocator);    // start from a specific locator
await reader.pause();
await reader.resume();
await reader.stop();
await reader.next();
await reader.previous();
await reader.audioSeekBy(const Duration(seconds: 30));
await reader.audioSeekBy(const Duration(seconds: -10));
```

## Updating preferences mid-session

```dart
await reader.audioSetPreferences(AudioPreferences(speed: 1.5));
```

## Playback state stream

```dart
_sub = reader.onTimebasedPlayerStateChanged.listen((state) {
  final progress = state.currentLocator?.locations?.totalProgression ?? 0.0;
  final elapsed  = state.currentTime;
  final total    = state.duration;

  switch (state.state) {
    case TimebasedState.playing: // update UI
    case TimebasedState.paused:  // show resume button
    case TimebasedState.ended:   // book finished
    case TimebasedState.failure: // handle error
    default: break;
  }
});
```

## Saving and restoring position

```dart
import 'dart:convert';
import 'package:rxdart/rxdart.dart';

_sub = reader.onTimebasedPlayerStateChanged
    .map((state) => state.currentLocator)
    .whereType<Locator>()
    .debounceTime(const Duration(seconds: 5))
    .listen((locator) {
  // Serialise the toJson() map however your storage layer expects.
  prefs.setString('audio_locator', jsonEncode(locator.toJson()));
});
```

Restore by passing `fromLocator` to `audioEnable`.

## Background playback

Background playback works automatically when `allowExternalSeeking: true` is set. Also declare the required permissions:

- **Android** — add `WAKE_LOCK` and `FOREGROUND_SERVICE` in `AndroidManifest.xml`
- **iOS** — add `audio` to `UIBackgroundModes` in `Info.plist`
