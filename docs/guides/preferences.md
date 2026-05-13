# Preferences

## EPUB display preferences

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  fontSize: 130,           // percentage: 50–200
  fontFamily: 'Georgia',
  verticalScroll: false,   // false = paginated, true = continuous scroll
  publisherStyles: true,
  lineHeight: 1.5,
  wordSpacing: 0.1,
  letterSpacing: 0.05,
  paragraphSpacing: 1.2,
  columnCount: 1,
));
```

### Theme presets

```dart
// Light
EPUBPreferences(backgroundColor: Colors.white, textColor: Colors.black)

// Sepia
EPUBPreferences(
  backgroundColor: const Color(0xFFFBF0D9),
  textColor: const Color(0xFF5B4636),
)

// Dark
EPUBPreferences(
  backgroundColor: const Color(0xFF1A1A1A),
  textColor: const Color(0xFFE0E0E0),
)
```

### Extended CSS properties

```dart
EPUBPreferences(cssProperties: {
  '--USER__lineHeight': '1.8',
  '--USER__firstLineIndent': '1rem',
})
```

See the [Readium CSS docs](https://github.com/readium/css) for all supported custom properties.

### Persisting preferences

```dart
// Save
prefs.setString('epub_prefs', jsonEncode(epubPrefs.toJson()));

// Restore
final json = prefs.getString('epub_prefs');
if (json != null) {
  await reader.setEPUBPreferences(
    EPUBPreferences.fromJson(jsonDecode(json) as Map<String, dynamic>),
  );
}
```

### Default preferences

Applied to all future publications, overridden per-session by `setEPUBPreferences`:

```dart
FlutterReadium().setDefaultPreferences(EPUBPreferences(fontSize: 110));
```

## TTS preferences

```dart
await reader.ttsSetPreferences(TTSPreferences(
  speed: 1.2,
  pitch: 1.0,
  voiceIdentifier: selectedVoice.identifier,
  language: 'en',
));
```

## Audio preferences

```dart
await reader.audioSetPreferences(AudioPreferences(
  speed: 1.0,
  pitch: 1.0,
  seekInterval: 30,
  allowExternalSeeking: true,
));
```
