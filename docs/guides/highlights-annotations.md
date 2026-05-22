# Highlights & Annotations

Decorations let you overlay highlights and underlines on the visual reader.

## Applying decorations

Decorations are grouped by an arbitrary string `id`. Re-applying with the same id **replaces** the entire group.

```dart
await reader.applyDecorations('highlights', [
  ReaderDecoration(
    id: 'h1',
    locator: myLocator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: const Color(0x99FFFF00), // semi-transparent yellow
    ),
  ),
  ReaderDecoration(
    id: 'h2',
    locator: anotherLocator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.underline,
      tint: Colors.blue,
    ),
  ),
]);
```

## Clearing a group

```dart
await reader.applyDecorations('highlights', []);
```

## Decoration styles

| Style | Visual |
|-------|--------|
| `DecorationStyle.highlight` | Background colour fill |
| `DecorationStyle.underline` | Underline |

Colours use Flutter `Color` values. The JSON representation uses `rgba(r, g, b, a)` notation.

## Typical group layout

```dart
// Keep groups separate for easier management
await reader.applyDecorations('highlights', highlights);
await reader.applyDecorations('bookmarks', bookmarks);
await reader.applyDecorations('search', searchResults);
```

## Persisting highlights

```dart
// Serialize
final json = highlight.toJson();
prefs.setString('highlight_${highlight.id}', jsonEncode(json));

// Restore and re-apply on book open
final stored = prefs.getKeys()
    .where((k) => k.startsWith('highlight_'))
    .map((k) => ReaderDecoration.fromJson(
          jsonDecode(prefs.getString(k)!) as Map<String, dynamic>))
    .toList();

await reader.applyDecorations('highlights', stored);
```

## TTS decoration styles

TTS uses a separate mechanism — see [Text-to-Speech](text-to-speech.md#decoration-styles-utterance--word-highlighting).
