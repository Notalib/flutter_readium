# EPUB Reading

This guide covers everything needed to build a fully-featured EPUB reader screen.

## Opening a publication

```dart
final reader = FlutterReadium();
late Publication _publication;

Future<void> _open(String url) async {
  try {
    _publication = await reader.openPublication(url);
  } on ReadiumException catch (e) {
    _showError('Cannot open (${e.code ?? e.codeEnum.name}): ${e.message}');
  }
}

@override
void dispose() {
  reader.closePublication();
  super.dispose();
}
```

## Displaying the reader

```dart
ReadiumReaderWidget(publication: _publication)
```

## Page navigation

```dart
await reader.goForward();
await reader.goBackward();
```

## Chapter navigation (TOC)

```dart
// Step through chapters
await reader.skipToNextTOC(
  publication: _publication,
  currentTocHref: _currentHref,
);
await reader.skipToPreviousTOC(
  publication: _publication,
  currentTocHref: _currentHref,
);

// Jump to an arbitrary TOC entry
final locator = _publication.locatorFromLink(tocEntry);
if (locator != null) await reader.goToLocator(locator);
```

Access the flattened TOC list via `_publication.tocFlattened`.

## Physical page numbers

Jump to a printed page number from the publication's page list:

```dart
await reader.toPhysicalPageIndex('42', _publication);
```

## Progress navigation

```dart
await reader.goToProgression(0.5); // 50% into the current resource
```

## Tracking position

```dart
late StreamSubscription _sub;

@override
void initState() {
  super.initState();
  _sub = reader.onTextLocatorChanged.listen((locator) {
    setState(() {
      _progress = locator.locations?.totalProgression ?? 0.0;
      _currentHref = locator.href;
    });
  });
}

@override
void dispose() {
  _sub.cancel();
  reader.closePublication();
  super.dispose();
}
```

## Persisting position

```dart
// Save — serialise locator.toJson() however your storage layer expects
prefs.setString('locator_${pub.metadata.identifier}', jsonEncode(locator.toJson()));

// Restore — pass as initialLocator
final stored = prefs.getString('locator_${pub.metadata.identifier}');
final saved = stored != null ? Locator.fromJsonString(stored) : null;

ReadiumReaderWidget(
  publication: _publication,
  initialLocator: saved,
)
```

## EPUB preferences

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  fontSize: 1.3,
  fontFamily: 'Georgia',
  scroll: false,
  publisherStyles: true,
));
```

See [Preferences](preferences.md) for all options.

## External links

```dart
ReadiumReaderWidget(
  publication: _publication,
  onExternalLinkActivated: (uri) {
    launchUrl(uri);
  },
)
```

## Searching

```dart
final results = await reader.searchInPublication('whale');
for (final r in results) {
  print('${r.locator.href} — ${r.text}');
}
```
