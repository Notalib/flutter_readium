# Locator

A `Locator` identifies an exact position within a publication resource. It is used for bookmarks, highlights, navigation, and progress tracking. See the Readium spec on the [Locator model](https://readium.org/architecture/models/locators/).

## Structure

```dart
Locator(
  href: '/OEBPS/chapter1.xhtml',  // resource path
  type: 'application/xhtml+xml',
  title: 'Chapter 1',
  locations: Locations(
    progression: 0.42,        // 0.0–1.0 within this resource
    totalProgression: 0.07,   // 0.0–1.0 across the whole publication
    position: 14,             // absolute page index (if available)
    cssSelector: '#p42',      // CSS selector pointing to the element
    fragments: ['page=42'],
  ),
  text: LocatorText(
    before: '...text before...',
    highlight: 'the highlighted text',
    after: '...text after...',
  ),
)
```

## Serialisation

`Locator` exposes a `toJson()` map and matching factories — serialise the map however your storage layer expects (e.g. `jsonEncode`, a database row, a message payload).

```dart
// To/from Map
final map  = locator.toJson();
final loc2 = Locator.fromJson(map);

// From a JSON string
final loc3 = Locator.fromJsonString(jsonString);

// Accept either a Map or a JSON string
final loc4 = Locator.fromJsonDynamic(anything);
```

### Note on href
`href` is stored decoded internally and percent-encoded during serialisation.

## Common patterns

```dart
// Display overall progress
final pct = (locator.locations?.totalProgression ?? 0) * 100;
print('${pct.toStringAsFixed(0)}%');

// Navigate
await FlutterReadium().goToLocator(locator);

// Convert a TOC link
final loc = pub.locatorFromLink(tocLink);
```

## Locations fields

| Field | Type | Description |
|-------|------|-------------|
| `progression` | `double?` | 0.0–1.0 within the current resource |
| `totalProgression` | `double?` | 0.0–1.0 across the whole publication |
| `position` | `int?` | Absolute page number (from page list) |
| `cssSelector` | `String?` | CSS selector for the target element |
| `domRange` | `String?` | DOM range (precise sub-element position) |
| `fragments` | `List<String>` | Additional URI fragments |

## Our additions to otherLocations

We try to enrich the Locator's `otherLocations` with the following data,
before it is sent over the bridge:

| Field | Type | Description |
|-------|------|-------------|
| `tocHref` | `string` | Current Table of Contents position in `href#identifier` format |
| `currentPage` | `int` | Current dynamic page-number of the rendered resource (starts from 1) |
| `totalPages` | `int` | Total number of dynamic pages of the rendered resource |
| `physicalPage` | `string` | Identifier for the most-recently passed physical page reference |
