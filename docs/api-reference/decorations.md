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
| `style` | `DecorationStyle` | `highlight`, `underline` or `marginMarker` |
| `tint` | `Color` | Colour of the decoration |
| `marker` | `MarginMarker?` | Label or icon to show. Required for `marginMarker` |

## DecorationStyle

| Value | Appearance |
|-------|-----------|
| `DecorationStyle.highlight` | Background colour fill over the text range |
| `DecorationStyle.underline` | Underline beneath the text range |
| `DecorationStyle.marginMarker` | Label or icon in the page margin, level with the first line of the range. See [Margin Markers](../guides/margin-markers.md) |

## MarginMarker

| Constructor | Description |
|-------------|-------------|
| `MarginMarker.label(String, {side})` | Text label, such as a page number |
| `MarginMarker.icon(MarginMarkerIcon, {side})` | Built-in icon (`MarginMarkerIcon.bookmark`) |

`side` is `MarginSide.start` (default) or `MarginSide.end`, and flips in right-to-left text.

## Applying decorations

```dart
await reader.applyDecorations('highlights', decorations);
```

Calling `applyDecorations` with the same group id **replaces** all existing decorations in that group. Pass an empty list to clear:

```dart
await reader.applyDecorations('highlights', []);
```

## Decoration taps

`onDecorationInteraction` on `ReadiumReaderWidget` fires when the user taps a decoration applied through `applyDecorations`. On web this covers highlight, underline and spotlight styles, and the event carries the group id you passed. Decorations that TTS and media overlay draw themselves are not tappable.

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
