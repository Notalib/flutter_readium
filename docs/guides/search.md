# Search

`FlutterReadium` exposes a full-text search API that runs against the resources of the currently open publication. Results come back as a list of `TextSearchResult` — each wrapping a `Locator` you can navigate to.

## Running a query

```dart
final results = await FlutterReadium().searchInPublication('whale');

for (final r in results) {
  print('${r.chapterTitle ?? '(untitled)'} — ${r.locator.text?.highlight}');
}
```

`searchInPublication` requires a publication to be open (see [openPublication](../api-reference/flutter-readium.md#publication-lifecycle)). It returns once the search has finished — there is no incremental result stream.

## Result shape

| Field | Type | Description |
|-------|------|-------------|
| `locator` | `Locator` | Position of the match. The `text` field contains the surrounding snippet (`before` / `highlight` / `after`). |
| `chapterTitle` | `String?` | Title of the chapter (or spine item) where the match was found, when available. |
| `pageNumbers` | `List<String>?` | Physical page references covering the match, when the publication declares a page list. |

## Navigating to a result

```dart
await FlutterReadium().goToLocator(result.locator);
```

The `locator.text` snippet is the publisher's text around the match, so it can be displayed in a result list without re-fetching the resource.

## Highlighting matches

Wrap the search results as `ReaderDecoration`s in a dedicated group so you can clear them later without affecting bookmarks or highlights:

```dart
final decorations = [
  for (final r in results)
    ReaderDecoration(
      id: 'search_${r.locator.href}_${r.locator.locations?.position ?? 0}',
      locator: r.locator,
      style: ReaderDecorationStyle(style: DecorationStyle.highlight, tint: Colors.yellow),
    ),
];

await FlutterReadium().applyDecorations('search', decorations);

// Clear later
await FlutterReadium().applyDecorations('search', const []);
```

See the [Highlights & Annotations guide](highlights-annotations.md) for the full decoration model.

## Platform notes

- Search is implemented by the upstream Readium toolkits — its accuracy and case sensitivity depend on the underlying engine on each platform.
- Search currently has no built-in cancellation. For long publications, consider debouncing user input and discarding results from previous queries.
