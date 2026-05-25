# Preferences

This guide covers all of the preferences APIs: EPUB display, TTS, and audio. As well as the plugin-specific options that this plugin layers on top of Readium's standard Preferences API.

## EPUB display preferences

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  fontSize: 130,           // percentage: 50–200
  fontFamily: 'Georgia',
  scroll: false,           // false = paginated, true = continuous scroll
  publisherStyles: true,
  lineHeight: 1.5,
  wordSpacing: 0.1,
  letterSpacing: 0.05,
  paragraphSpacing: 1.2,
  columnCount: EpubColumnCount.one,
));
```

### Theme colors

Use `backgroundColor` and `textColor` to apply themed color schemes:

```dart
// Sepia
EPUBPreferences(
  backgroundColor: const Color(0xFFF4ECD8),
  textColor: const Color(0xFF5C4B2A),
)

// Dark
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

## Plugin-specific preferences

The following `EPUBPreferences` fields are not part of the Readium Preferences API but are added by this plugin to support app-level behavior.

### `firstElementTopMargin`

Adds a top margin (in pixels) to the first element of each spine item. Use this to prevent content from being obscured by a floating toolbar or status bar overlay.

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  firstElementTopMargin: 56, // match your AppBar height
));
```

The margin is re-applied whenever the chapter changes, so you only need to set it once.

### `blackAndWhiteComicMode`

Applies a black-and-white filter to the entire page. Intended for comic books. When `true`, any `imageFilter` setting is ignored.

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  blackAndWhiteComicMode: true,
));
```

Defaults to `false`.

### `disableSynchronization`

Prevents the TTS and Sync-Audio navigators from scrolling the visual EPUB view or switching chapters as playback progresses. Highlight decorations (word/sentence highlighting) still apply — only the automatic navigation is suppressed.

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  disableSynchronization: true,
));
```

Defaults to `false`.
