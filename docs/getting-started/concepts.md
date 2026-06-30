# Core Concepts

To properly use Flutter Readium, it will be very helpful to familiarize yourself with the following core concepts.

## Publication

A `Publication` is the loaded container for an ebook, audiobook, or WebPub. It follows the [Readium Web Publication Manifest](https://readium.org/webpub-manifest/) format.

Use `loadPublication` to fetch just the manifest (for example, to populate a bookshelf). Use `openPublication` before any reading, navigation, audio, or TTS operation — it initialises the native reader for that publication.

```dart
final pub = await FlutterReadium().openPublication(url);

print(pub.metadata.title);             // "Moby Dick"
print(pub.conformsToReadiumEbook);     // true if it declares the Readium EPUB profile
print(pub.conformsToReadiumAudiobook); // true if it declares the Readium Audiobook profile
print(pub.containsMediaOverlays);      // true for sync-narration books with media-overlays
print(pub.coverUri);                   // Uri? for the cover image
```

Key properties: `metadata`, `readingOrder`, `tableOfContents` (aliased as `toc`), `resources`, `pageList`.

See guide for [EPUB Reading](../guides/epub-reading.md) for more details.

## Locator

A `Locator` pinpoints an exact position inside a resource. It is the currency for bookmarks, highlights, and navigation.

```dart
// Progression within the whole publication (0.0 → 1.0)
final total = locator.locations?.totalProgression;

// Progression within the current resource (0.0 → 1.0)
final local = locator.locations?.progression;

// Persist — serialise the map however your storage layer expects
final map = locator.toJson();

// Restore — accepts either a Map or a JSON string
final restored = Locator.fromJsonDynamic(stored);

// Navigate
if (restored != null) {
  await FlutterReadium().goToLocator(restored);
}
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
| Audiobook | Readium Audiobook | `audioEnable()` |
| MediaOverlay (sync narration) | WebPub + media-overlays | `audioEnable()` |
| TTS | any visual | `ttsEnable()` |

Navigation methods (`goForward`, `goBackward`, `goToLocator`, `goToProgression`) are shared across modes.

## Event streams

The plugin communicates state changes through four streams:

```dart
final reader = FlutterReadium();

reader.onTextLocatorChanged.listen((locator) { /* position updated */ });
reader.onTimebasedPlayerStateChanged.listen((state) { /* audio/TTS state */ });
reader.onReaderStatusChanged.listen((status) { /* loading, ready, closed, reachedEndOfPublication, error */ });
reader.onErrorEvent.listen((error) { /* non-fatal errors */ });
```

Always cancel subscriptions in `dispose()` to avoid leaks.

See guides for [Saving Progress](../guides/saving-progress.md) or [Error Handling](../guides/error-handling.md) for more details.

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

See guide for [Highlights & Annotations](../guides/highlights-annotations.md) for more details.

## Preferences

`EPUBPreferences` controls the visual appearance of the reader. Pass it to `setEPUBPreferences` at any time:

```dart
await reader.setEPUBPreferences(
  EPUBPreferences(
    fontSize: 1.4,
    fontFamily: 'Helvetica',
    scroll: true, // vertical scroll instead of horizontal pagination
    publisherStyles: false,
  ),
);
```

See guide for [Preferences](../guides/preferences.md) for more details.
