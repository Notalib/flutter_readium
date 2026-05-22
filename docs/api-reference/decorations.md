# Decorations

Decorations overlay visual markers (highlights, underlines) on the reader.

## ReaderDecoration

```dart
ReaderDecoration(
  id: 'unique-id',          // unique within the group
  locator: myLocator,       // where to apply the decoration
  style: ReaderDecorationStyle(
    style: DecorationStyle.highlight,
    tint: const Color(0x99FFFF00),
  ),
)
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier within the group |
| `locator` | `Locator` | Position and range of the decoration |
| `style` | `ReaderDecorationStyle` | Visual appearance |

## ReaderDecorationStyle

| Field | Type | Description |
|-------|------|-------------|
| `style` | `DecorationStyle` | `highlight` or `underline` |
| `tint` | `Color` | Colour of the decoration |

## DecorationStyle

| Value | Appearance |
|-------|-----------|
| `DecorationStyle.highlight` | Background colour fill over the text range |
| `DecorationStyle.underline` | Underline beneath the text range |

## Applying decorations

```dart
await reader.applyDecorations('highlights', decorations);
```

Calling `applyDecorations` with the same group id **replaces** all existing decorations in that group. Pass an empty list to clear:

```dart
await reader.applyDecorations('highlights', []);
```

## Serialisation

```dart
// Save
final map = decoration.toJson();

// Restore
final decoration = ReaderDecoration.fromJson(map);
```

## TTS decoration styles

TTS highlights are configured separately via `setDecorationStyle`:

```dart
await reader.setDecorationStyle(
  ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.yellow),
  ReaderDecorationStyle(style: DecorationStyle.underline, tint: Colors.orange),
);
```
