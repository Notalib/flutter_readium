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

The `theme` property (of type `EpubThemeType`) is a shortcut that applies a predetermined `backgroundColor` and `textColor` pair. When set, it overrides any explicit `backgroundColor` / `textColor` preferences.

```dart
// Built-in presets: light, sepia, dark
EPUBPreferences(theme: EpubThemeType.light)
EPUBPreferences(theme: EpubThemeType.sepia)
EPUBPreferences(theme: EpubThemeType.dark)
```

For custom themes, leave `theme` unset and provide your own colors:

```dart
EPUBPreferences(
  backgroundColor: const Color(0xFF002B36),
  textColor: const Color(0xFF839496),
)
```

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
