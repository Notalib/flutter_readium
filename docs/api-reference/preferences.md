# Preferences

## EPUBPreferences

Controls the visual appearance of the EPUB reader.

| Field | Type | Description |
|-------|------|-------------|
| `fontSize` | `int?` | Font size percentage (50–200, where 100 = default) |
| `fontFamily` | `String?` | Font family name |
| `fontWeight` | `int?` | Font weight (400 = normal, 700 = bold) |
| `verticalScroll` | `bool?` | `true` = continuous scroll, `false` = paginated |
| `publisherStyles` | `bool?` | Respect the publisher's CSS (`true` by default) |
| `lineHeight` | `double?` | Line height multiplier |
| `wordSpacing` | `double?` | Additional word spacing (em units) |
| `letterSpacing` | `double?` | Additional letter spacing (em units) |
| `paragraphSpacing` | `double?` | Paragraph spacing multiplier |
| `columnCount` | `int?` | Number of columns (1 or 2) |
| `textAlignment` | `String?` | `'justify'`, `'left'`, `'right'`, `'center'` |
| `backgroundColor` | `Color?` | Background colour |
| `textColor` | `Color?` | Text colour |
| `verticalWriting` | `bool?` | Enable vertical writing mode |
| `cssProperties` | `Map<String, String>?` | Custom CSS variable overrides |
| `firstElementMargin` | `double?` | Top margin of the first element |

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  fontSize: 130,
  fontFamily: 'Georgia',
  verticalScroll: false,
));
```

## TTSPreferences

| Field | Type | Description |
|-------|------|-------------|
| `speed` | `double?` | Speech rate multiplier (1.0 = normal) |
| `pitch` | `double?` | Pitch multiplier (1.0 = normal) |
| `voiceIdentifier` | `String?` | Voice identifier from `ttsGetAvailableVoices()` |
| `language` | `String?` | BCP 47 language tag override |

```dart
await reader.ttsSetPreferences(TTSPreferences(speed: 1.3));
```

## AudioPreferences

| Field | Type | Description |
|-------|------|-------------|
| `speed` | `double?` | Playback speed multiplier |
| `pitch` | `double?` | Pitch multiplier |
| `seekInterval` | `int?` | Seconds per `audioSeekBy` call |
| `allowExternalSeeking` | `bool?` | Enable lock screen / notification controls |
| `controlPanelInfoType` | `ControlPanelInfoType?` | What to display in the system control panel |

```dart
await reader.audioSetPreferences(AudioPreferences(speed: 1.5, seekInterval: 30));
```
