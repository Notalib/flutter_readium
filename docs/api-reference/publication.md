# Publication

`Publication` is the top-level container for a loaded ebook, audiobook, or WebPub. It follows the [Readium Web Publication Manifest](https://readium.org/webpub-manifest/) format.

## Key properties

| Property | Type | Description |
|----------|------|-------------|
| `metadata` | `Metadata` | Title, authors, language, identifier, date |
| `readingOrder` | `List<Link>` | Ordered list of content resources |
| `tableOfContents` | `List<Link>` | Hierarchical navigation structure |
| `resources` | `List<Link>` | Images, fonts, stylesheets |
| `pageList` | `List<Link>` | Physical page list (if present) |
| `subCollections` | `Map<String, List<Link>>` | Named sub-collections (landmarks, etc.) |

## Computed helpers

```dart
pub.coverUri                    // Uri? of the cover image
pub.conformsToReadiumEbook      // true for EPUB/WebPub text
pub.conformsToReadiumAudiobook  // true for audiobook
pub.containsMediaOverlays       // true for sync-narration
pub.metadata.identifier         // e.g. "urn:isbn:9780000000000"
pub.tocFlattened                // flat List<Link> from nested TOC
```

## Navigation

```dart
// Convert a TOC link to a Locator for goToLocator
final locator = pub.locatorFromLink(tocLink);

// Navigate by link directly
await reader.goByLink(tocLink, pub);

// Physical page jump
await reader.toPhysicalPageIndex('42', pub);
```

## Metadata fields

| Field | Type | Description |
|-------|------|-------------|
| `localizedTitle` | `LocalizedString` | Title in one or more languages |
| `title` | `String` | Title in the default language |
| `authors` | `List<Contributor>` | Author contributors |
| `language` | `String?` | BCP 47 primary language |
| `identifier` | `String?` | Unique publication identifier |
| `published` | `DateTime?` | Publication date |
| `numberOfPages` | `int?` | Total physical page count |

## Link fields

| Field | Type | Description |
|-------|------|-------------|
| `href` | `String` | Resource path or URL |
| `type` | `String?` | MIME type |
| `title` | `String?` | Human-readable label |
| `children` | `List<Link>` | Nested entries (TOC sub-sections) |

## Serialisation

```dart
final json  = pub.toJson();
final pub2  = Publication.fromJson(json);
```
