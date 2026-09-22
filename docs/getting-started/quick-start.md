# Quick Start

This guide takes you from zero to a working reader screen in a couple of minutes.

## 1. Open a publication

Start with the complete [`ReaderScreen` example](../../flutter_readium/README.md#quick-start). It opens a
publication URL, mounts `ReadiumReaderWidget`, handles loading and errors, and closes the publication when
the screen is disposed. Complete the [platform setup](installation.md) before running it.

## 2. Add navigation controls

```dart
Row(
  children: [
    IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => _readium.goBackward(),
    ),
    IconButton(
      icon: const Icon(Icons.arrow_forward),
      onPressed: () => _readium.goForward(),
    ),
  ],
)
```

## 3. Track reading position

In `_ReaderScreenState`, add a progress field and keep the subscription so it can be canceled:

```dart
StreamSubscription<Locator>? _positionSubscription;
double _progress = 0;

@override
void initState() {
  super.initState();
  _positionSubscription = _readium.onTextLocatorChanged.listen((locator) {
    final progress = locator.locations?.totalProgression ?? 0.0;
    if (mounted) setState(() => _progress = progress);
  });
  _open();
}
```

Call `_positionSubscription?.cancel()` in the screen's existing `dispose()` method.

## 4. Apply EPUB display preferences

```dart
await _readium.setEPUBPreferences(
  EPUBPreferences(
    fontSize: 1.2,          // 120% of default
    fontFamily: 'Georgia',
    scroll: false,          // paginated mode
  ),
);
```

## 5. Restore a saved position

```dart
// On open — pass a previously saved Locator
ReadiumReaderWidget(
  publication: _publication!,
  initialLocator: _savedLocator, // nullable
)

// Save when position changes — serialise locator.toJson() however your storage layer expects
  _readium.onTextLocatorChanged.listen((locator) {
  prefs.setString('lastLocator', jsonEncode(locator.toJson()));
});

// Restore
final stored = prefs.getString('lastLocator')!;
final locator = Locator.fromJsonString(stored);
```

## Next steps

- [EPUB Reading guide](../guides/epub-reading.md) — full navigation, TOC, and external links
- [Audiobook Playback](../guides/audiobook-playback.md)
- [Text-to-Speech](../guides/text-to-speech.md)
- [Saving Progress](../guides/saving-progress.md)
