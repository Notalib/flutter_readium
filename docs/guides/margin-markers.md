# Margin Markers

A margin marker is a small label or icon in the page margin, level with the first line of a text location. Use it for printed page numbers, bookmarks, or any note-style flag that should not cover the text.

Markers are decorations with the `DecorationStyle.marginMarker` style, so they follow the same group rules as [highlights](highlights-annotations.md): re-applying a group replaces it, and an empty list clears it. They are supported for EPUB on iOS, Android and web. PDF navigators do not support decorations.

## The marker

`ReaderDecorationStyle.marker` is required for `marginMarker` and ignored for other styles. A marker is either a text label or a built-in icon:

```dart
const MarginMarker.label('12', side: MarginSide.end, anchor: MarginAnchor.page)
const MarginMarker.icon(MarginMarkerIcon.bookmark) // side defaults to MarginSide.start, anchor to MarginAnchor.text
```

The fields are described in the [API reference](../api-reference/decorations.md#marginmarker).

`tint` colours the marker's label or icon. Without a tint the marker uses the publication's text colour, so it follows the reader theme. Labels are drawn slightly muted. `isActive` is ignored.

## Anchoring

`anchor` decides where the marker sits inside the margin:

- `MarginAnchor.page` puts the marker near the page edge, or the column edge in two-column layouts. On a wide screen this can be far from the text, which suits printed page numbers.
- `MarginAnchor.text` (default) keeps the marker a small gap (half the body font size) from the text column, however wide the margin is. Use it for markers that belong to a passage, such as bookmarks.

A text-anchored marker follows font size, page margins, scroll mode and publisher CSS. When the margin is narrower than the marker, it overflows toward the text rather than off the page; [`makeSpaceForMarginDecoration`](#margin-width) prevents that. It lines up with the body's text column, so paragraphs that the publisher indents further keep their extra indent.

A `marginMarker` decoration without a label or icon is skipped and logged. In debug builds, `applyDecorations` asserts that the marker is present.

## Recipe: page numbers

Print-equivalent EPUBs carry a `pageList` navigation document. Map each entry to a locator and apply one marker per entry:

```dart
Future<void> showPageNumbers(Publication publication) {
  final decorations = <ReaderDecoration>[];
  for (final (index, link) in publication.pageList.indexed) {
    final title = link.title;
    final locator = publication.locatorFromLink(link);
    if (title == null || locator == null) continue;
    decorations.add(
      ReaderDecoration(
        id: 'page_$index',
        locator: locator,
        style: ReaderDecorationStyle(
          style: DecorationStyle.marginMarker,
          marker: MarginMarker.label(title, side: MarginSide.end, anchor: MarginAnchor.page),
        ),
      ),
    );
  }
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

## Margin width

Markers are sized with the font, but Readium's page margin is a fixed number of pixels (scaled by `pageMargins`). At large font sizes, or with small `pageMargins`, a marker can therefore overlap the text. You cannot fix this with `pageMargins` alone, because the publication's base font size is not exposed.

Set `makeSpaceForMarginDecoration` to let the plugin size the margin instead:

```dart
await reader.setEPUBPreferences(prefs.copyWith(makeSpaceForMarginDecoration: true));
```

The side margins then grow with the font size, enough for an icon or a page number of up to three digits with either [anchor](#anchoring). Longer labels can still reach the text. They are never narrower than `pageMargins` would make them. Turning it on shortens the lines, so the text re-paginates like any other layout change. It also applies in scroll mode, and it is ignored for fixed-layout publications.

The margin is reserved on both sides, whether or not any marker is showing. Leave it off if you do not show margin markers.

## Layout notes

- **Two columns.** The `end` margin of the left column and the `start` margin of the right column are the same gap, so markers on both sides can overlap there.
- **Vertical writing modes** are not supported.
- **Fixed layout on iOS.** Decorations are duplicated on both pages of a two-page spread until swift-toolkit 4.0.
- **Volume.** A long book can have hundreds of page-list entries. Apply them in one `applyDecorations` call rather than one call per entry.

See also the [decorations API reference](../api-reference/decorations.md).
