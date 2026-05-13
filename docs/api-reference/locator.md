# Locator

A `Locator` identifies an exact position within a publication resource. It is used for bookmarks, highlights, navigation, and progress tracking.

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

```dart
// To string (for SharedPreferences / database)
final json = locator.json;

// From string
final restored = Locator.fromJsonString(json);

// To/from Map
final map  = locator.toJson();
final loc2 = Locator.fromJson(map);
```

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
