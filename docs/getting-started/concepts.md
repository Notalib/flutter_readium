# Core Concepts

Understanding a handful of types makes everything else click.

## Publication

A `Publication` is the loaded container for an ebook, audiobook, or WebPub. It follows the [Readium Web Publication Manifest](https://readium.org/webpub-manifest/) format.

```dart
final pub = await FlutterReadium().openPublication(url);

print(pub.metadata.title);            // "Moby Dick"
print(pub.conformsToReadiumEbook);    // true for EPUB/WebPub
print(pub.containsMediaOverlays);     // true for sync-narration books
print(pub.coverUri);                  // Uri? for the cover image
```

Key properties: `metadata`, `readingOrder`, `tableOfContents`, `resources`, `pageList`.

## Locator

A `Locator` pinpoints an exact position inside a resource. It is the currency for bookmarks, highlights, and navigation.

```dart
// Progression within the whole publication (0.0 → 1.0)
final total = locator.locations?.totalProgression;

// Progression within the current resource (0.0 → 1.0)
final local = locator.locations?.progression;

// Persist
final json = locator.json;

// Restore
final restored = Locator.fromJsonString(json);

// Navigate
await FlutterReadium().goToLocator(restored);
```

## Link

A `Link` references a resource within or outside the publication — table-of-contents entries, cover images, reading-order items. Convert one to a `Locator` for navigation:

```dart
final locator = pub.locatorFromLink(tocLink);
if (locator != null) {
  await reader.goToLocator(locator);
}
```

Nested TOC entries are accessed via `link.children`. Use `pub.tocFlattened` to get a flat list.

## Reading modes

| Mode | Publication type | Enable via |
|------|-----------------|------------|
| Visual (EPUB/WebPub) | EPUB, WebPub | `openPublication` + `ReadiumReaderWidget` |
| Audiobook | `.audiobook` | `audioEnable()` |
| MediaOverlay (sync narration) | WebPub + overlays | `audioEnable()` |
| TTS | any visual | `ttsEnable()` |

Navigation methods (`goForward`, `goBackward`, `goToLocator`, `goToProgression`) are shared across modes.

## Event streams

The plugin communicates state changes through four streams:

```dart
final reader = FlutterReadium();

reader.onTextLocatorChanged.listen((locator) { /* position updated */ });
reader.onTimebasedPlayerStateChanged.listen((state) { /* audio/TTS state */ });
reader.onReaderStatusChanged.listen((status) { /* loading, ready, … */ });
reader.onErrorEvent.listen((error) { /* non-fatal errors */ });
```

Always cancel subscriptions in `dispose()` to avoid leaks.

## Decorations

Decorations overlay highlights and underlines on the visual reader. They are grouped by an arbitrary string `id`; re-applying with the same id replaces the group.

```dart
await reader.applyDecorations('highlights', [
  ReaderDecoration(
    id: 'h1',
    locator: myLocator,
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: Colors.yellow,
    ),
  ),
]);

// Clear the group
await reader.applyDecorations('highlights', []);
```

## Preferences

`EPUBPreferences` controls the visual appearance of the reader. Pass it to `setEPUBPreferences` at any time:

```dart
await reader.setEPUBPreferences(
  EPUBPreferences(
    fontSize: 140,
    fontFamily: 'Helvetica',
    verticalScroll: true,
    publisherStyles: false,
  ),
);
```

See [Preferences guide](../guides/preferences.md) for the full option list.
