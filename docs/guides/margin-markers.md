# Margin Markers

A margin marker is a small label or icon in the page margin, level with the first line of a text location. Use it for printed page numbers, bookmarks, or any note-style flag that should not cover the text.

Markers are decorations with the `DecorationStyle.marginMarker` style, so they follow the same group rules as [highlights](highlights-annotations.md): re-applying a group replaces it, and an empty list clears it. They are supported for EPUB on iOS, Android and web. PDF navigators do not support decorations.

## The marker

`ReaderDecorationStyle.marker` is required for `marginMarker` and ignored for other styles. A marker is either a text label or a built-in icon:

```dart
const MarginMarker.label('12', side: MarginSide.end)
const MarginMarker.icon(MarginMarkerIcon.bookmark) // side defaults to MarginSide.start
```

| Field | Description |
|-------|-------------|
| `label` | Short text, such as a page number. Escaped before rendering |
| `icon` | One of the built-in icons (`MarginMarkerIcon.bookmark`). The set is closed: the plugin never renders app-supplied markup |
| `side` | `MarginSide.start` or `MarginSide.end`. Logical, so `start` is the left margin in left-to-right text and the right margin in right-to-left text |

`tint` colours the marker's text, border and icon. Without a tint the marker uses the publication's text colour. `isActive` is ignored. The marker background follows the reader theme.

A `marginMarker` decoration without a label or icon is skipped and logged. In debug builds, `applyDecorations` asserts that the marker is present.

## Recipe: page numbers

Print-equivalent EPUBs carry a `pageList` navigation document. Map each entry to a locator and apply one marker per entry:

```dart
Future<void> showPageNumbers(Publication publication) {
  final decorations = <ReaderDecoration>[
    for (final (index, link) in publication.pageList.indexed)
      if (link.title != null && publication.locatorFromLink(link) != null)
        ReaderDecoration(
          id: 'page_$index',
          locator: publication.locatorFromLink(link)!,
          style: ReaderDecorationStyle(
            style: DecorationStyle.marginMarker,
            marker: MarginMarker.label(link.title!, side: MarginSide.end),
          ),
        ),
  ];
  return FlutterReadium().applyDecorations('page-list', decorations);
}

Future<void> hidePageNumbers() => FlutterReadium().applyDecorations('page-list', []);
```

Use `pageList`, not `pageListOrGenerated`: generated entries are PDF links. The example app has this behind a toggle in the player app bar.

## Recipe: bookmarked highlights

Apply a second group with one icon marker per highlight, on the same locator as the highlight:

```dart
await reader.applyDecorations('highlights', [
  for (final h in highlights)
    ReaderDecoration(
      id: h.id,
      locator: h.locator,
      style: ReaderDecorationStyle(style: DecorationStyle.highlight, tint: h.color),
    ),
]);

await reader.applyDecorations('highlight-markers', [
  for (final h in highlights)
    ReaderDecoration(
      id: '${h.id}_marker',
      locator: h.locator,
      style: const ReaderDecorationStyle(
        style: DecorationStyle.marginMarker,
        tint: Color(0xFF2E7D32),
        marker: MarginMarker.icon(MarginMarkerIcon.bookmark),
      ),
    ),
]);
```

Re-apply both groups together whenever the highlights change, so markers never outlive their highlight.

## Taps

A marker only reacts to taps on the marker itself, not on the row of text beside it, so taps on the highlighted text still reach the highlight. A tap on the marker reports a normal `onDecorationInteraction` event with the marker's group. Ignore groups you do not handle:

```dart
onDecorationInteraction: (event) {
  if (event.group != 'highlights') return;
  // open the highlight sheet
},
```

Pair a marker with a text decoration if tapping the location should do something. Markers are additive; the plugin has no option to suppress marker taps.

## Layout notes

- **Margin width.** Markers sit in the page margin. Icons need a little more room than page numbers, and with small `pageMargins` a marker can overlap the text. The plugin does not compensate for this.
- **Two columns.** The `end` margin of the left column and the `start` margin of the right column are the same gap, so markers on both sides can overlap there.
- **Vertical writing modes** are not supported.
- **Fixed layout on iOS.** Decorations are duplicated on both pages of a two-page spread until swift-toolkit 4.0.
- **Volume.** A long book can have hundreds of page-list entries. Apply them in one `applyDecorations` call rather than one call per entry.

See also the [decorations API reference](../api-reference/decorations.md).
