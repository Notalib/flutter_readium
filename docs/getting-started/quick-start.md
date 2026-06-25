# Quick Start

This guide takes you from zero to a working reader screen in a couple of minutes.

## 1. Open a publication

```dart
import 'package:flutter_readium/flutter_readium.dart';

class ReaderScreen extends StatefulWidget {
  final String pubUrl;
  const ReaderScreen({super.key, required this.pubUrl});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _reader = FlutterReadium();
  Publication? _publication;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final pub = await _reader.openPublication(widget.pubUrl);
      setState(() => _publication = pub);
    } on ReadiumException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _reader.closePublication();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    if (_publication == null) return const Center(child: CircularProgressIndicator());

    return ReadiumReaderWidget(publication: _publication!);
  }
}
```

## 2. Add navigation controls

```dart
Row(
  children: [
    IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => _reader.goBackward(),
    ),
    IconButton(
      icon: const Icon(Icons.arrow_forward),
      onPressed: () => _reader.goForward(),
    ),
  ],
)
```

## 3. Track reading position

```dart
@override
void initState() {
  super.initState();
  _reader.onTextLocatorChanged.listen((locator) {
    final progress = locator.locations?.totalProgression ?? 0.0;
    setState(() => _progress = progress);
  });
  _open();
}
```

## 4. Apply EPUB display preferences

```dart
await _reader.setEPUBPreferences(
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
_reader.onTextLocatorChanged.listen((locator) {
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
