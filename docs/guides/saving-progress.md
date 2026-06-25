# Saving Progress

This guide focuses on *when* and *where* to persist a `Locator`. For the full set of serialization factories (`fromJson`, `fromJsonString`, `fromJsonDynamic`) and the `Locations` field reference, see the [Locator API reference](../api-reference/locator.md).

## Basic pattern

1. Listen to `onTextLocatorChanged`
2. Debounce writes (saves per scroll event are too frequent)
3. Persist `locator.toJson()` keyed by publication identifier — serialise the map however your storage layer expects
4. On re-open, pass the restored `Locator` as `initialLocator`

```dart
import 'dart:convert';
import 'package:rxdart/rxdart.dart';

_sub = reader.onTextLocatorChanged
    .debounceTime(const Duration(seconds: 2))
    .listen((locator) {
  final key = 'locator_${_publication.metadata.identifier}';
  prefs.setString(key, jsonEncode(locator.toJson()));
});
```

## Restoring position

```dart
final key = 'locator_${pub.metadata.identifier}';
final stored = prefs.getString(key);
final saved = stored != null ? Locator.fromJsonString(stored) : null;

ReadiumReaderWidget(
  publication: pub,
  initialLocator: saved,   // null = start from beginning
)
```

## Key the locator by publication identifier — not file path

File paths change when the app is reinstalled or the file is moved. Use the stable identifier from the publication manifest:

```dart
pub.metadata.identifier  // e.g. "urn:isbn:9780000000000"
```

If the publication has no identifier, fall back to a hash of the URL.

## Saving audio / TTS position

For timebased playback, save `state.currentLocator` from `onTimebasedPlayerStateChanged`:

```dart
_sub = reader.onTimebasedPlayerStateChanged
    .map((state) => state.currentLocator)
    .whereType<Locator>()
    .debounceTime(const Duration(seconds: 5))
    .listen((locator) {
  prefs.setString('audio_${pub.metadata.identifier}', jsonEncode(locator.toJson()));
});
```

## Comics (DiViNa): persist both locator types

For comic playback, persist **both** streams:

1. `onTextLocatorChanged` for visual/page resume (`image0007.jpg`)
2. `onTimebasedPlayerStateChanged.currentLocator` for narration/audio resume (`chapter01.mp3#t=...`)

At restore time:

1. Opening the reader (no autoplay): use the saved **text locator** as `initialLocator`
2. Starting/resuming narration: use the saved **timebased locator** for `play(fromLocator:)` / `audioEnable(fromLocator:)`

This avoids ambiguity: text locators are page-oriented, while timebased locators are playback-oriented.

## Prefer enriched locators

When available, keep locators that include `cssSelector` or `domRange` in `locations`. These give Readium more precision on restoration, especially across re-flows from font size changes.

## Storage options

| Option | Best for |
|--------|----------|
| `shared_preferences` | Single device, simple use-cases |
| `sqflite` / `drift` | Reading history, bookmarks, highlights |
| Firebase / cloud | Cross-device sync |

## Conflict resolution

When merging saved positions from multiple devices, prefer the higher `totalProgression` value — it represents further progress through the book.
