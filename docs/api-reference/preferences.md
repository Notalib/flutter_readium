# Preferences

## EPUBPreferences

Controls the visual appearance of the EPUB reader. All fields are optional unless noted; omitted fields leave the current value unchanged.

### Typography

| Field | Type | Description |
|-------|------|-------------|
| `fontFamily` | `String?` | Font family name. |
| `fontSize` | `int?` | Font size as a percentage of the base size (100 = default). |
| `fontWeight` | `double?` | Font weight (400 = normal, 700 = bold). |
| `lineHeight` | `double?` | Line height multiplier. |
| `letterSpacing` | `double?` | Additional letter spacing (em units). |
| `wordSpacing` | `double?` | Additional word spacing (em units). |
| `paragraphSpacing` | `double?` | Paragraph spacing (em units). |
| `paragraphIndent` | `double?` | First-line paragraph indent (em units). |
| `typeScale` | `double?` | Scale applied to all element font sizes. |
| `textAlign` | `TextAlign?` | Flutter `TextAlign` enum (`left`, `right`, `center`, `justify`, `start`, `end`). |
| `hyphens` | `bool?` | Enable hyphenation. |
| `ligatures` | `bool?` | Enable ligatures. |
| `textNormalization` | `bool?` | Normalize text styles to increase accessibility. |

### Layout

| Field | Type | Description |
|-------|------|-------------|
| `columnCount` | `EpubColumnCount?` | One of `auto`, `one`, `two`. |
| `scroll` | `bool?` | `true` = continuous scroll, `false` = paginated (default). |
| `spread` | `String?` | Synthetic spread mode for fixed-layout publications (e.g. `auto`, `never`, `always`). |
| `pageMargins` | `double?` | Page margin multiplier. |
| `verticalText` | `bool?` | Lay out text vertically (CJK). Auto-derived from `language` if not set. |
| `readingProgression` | `EpubReadingProgression?` | `ltr` or `rtl`. |
| `firstElementTopMargin` | `int?` | Top margin applied to the first element, in pixels — useful to clear a toolbar. Custom plugin setting |

### Theme & color

| Field | Type | Description |
|-------|------|-------------|
| `backgroundColor` | `Color?` | Page background color. |
| `textColor` | `Color?` | Text color. |

### Content

| Field | Type | Description |
|-------|------|-------------|
| `language` | `String?` | BCP 47 language tag (e.g. `en`, `fr`, `zh-CN`). |
| `publisherStyles` | `bool?` | Respect the publisher's CSS. Many typography settings require this to be `false` to take effect. |
| `imageFilter` | `EpubImageFilter?` | `darken` or `invert`. Ignored when `blackAndWhiteComicMode` is enabled. |
| `blackAndWhiteComicMode` | `bool` | Apply a black-and-white filter to comic book pages. Defaults to `false`. Takes precedence over `imageFilter`. |
| `disableSynchronization` | `bool` | Disable position synchronization between the TTS / SyncAudio navigators and the EPUB navigator. Defaults to `false`. Highlight decorations still apply, but the view won't scroll or switch chapter automatically. |

```dart
await reader.setEPUBPreferences(EPUBPreferences(
  fontSize: 130,
  fontFamily: 'Georgia',
  scroll: false,
));
```

## PDFPreferences

Controls the visual appearance of the PDF reader. All fields are optional; omitted fields leave the current value unchanged.

| Field | Type | Description |
|-------|------|-------------|
| `layout` | `PDFLayout?` | One of `paginated`, `scrollVertical`, `scrollHorizontal`. |
| `readingProgression` | `PDFReadingProgression?` | `ltr` or `rtl`. |
| `pageSpacing` | `double?` | Spacing between pages. Supported on iOS + Android. Must be `>= 0`. |
| `fit` | `PDFFit?` | One of `auto`, `page`, `width`. iOS supports all values. Android supports `page` + `width`; `auto` is ignored on Android. |
| `offsetFirstPage` | `bool?` | When `true`, the first page is displayed alone rather than paired in two-up view. Useful when the cover is page 1. **iOS only.** |
| `spread` | `PDFSpread?` | Synthetic spread (dual-page view) mode: `auto`, `never`, `always`. **iOS only.** |
| `visibleScrollbar` | `bool?` | Whether the scroll indicator is shown while scrolling. **iOS only.** |

```dart
await reader.setPDFPreferences(const PDFPreferences(
  layout: PDFLayout.paginated,
  pageSpacing: 12,
  fit: PDFFit.page,
));
```

## TTSPreferences

| Field | Type | Description |
|-------|------|-------------|
| `speed` | `double?` | Speech rate multiplier (1.0 = normal). |
| `pitch` | `double?` | Pitch multiplier (1.0 = normal). |
| `voiceIdentifier` | `String?` | Voice identifier from `ttsGetAvailableVoices()`. |
| `voices` | `Map<String, String>` | Per-language voice identifiers, keyed by BCP 47 language tag. Used on Android to pick a voice when the publication switches language. Defaults to `{}`. |
| `languageOverride` | `String?` | Force a language for TTS, ignoring the publication's declared language. BCP 47 tag. |
| `controlPanelInfoType` | `ControlPanelInfoType?` | What metadata to display in the system control panel during TTS playback. See [ControlPanelInfoType](#controlpanelinfotype). |
| `controlPanelTimebase` | `ControlPanelTimebase?` | Timeline basis used by system media controls. See [ControlPanelTimebase](#controlpaneltimebase). Defaults to `chapter` when omitted or unknown during deserialization. |

```dart
await reader.ttsSetPreferences(TTSPreferences(speed: 1.3));
```

## AudioPreferences

| Field | Type | Description |
|-------|------|-------------|
| `volume` | `double?` | Playback volume. |
| `speed` | `double?` | Playback speed multiplier (1.0 = normal). |
| `pitch` | `double?` | Pitch multiplier (1.0 = normal). |
| `seekInterval` | `double?` | Interval in seconds skipped by `goForward` / `goBackward`. |
| `allowExternalSeeking` | `bool?` | Allow seeking from the system's media controls (iOS Control Center / lock screen, Android notification). When `false`, the seek bar in those surfaces is read-only. |
| `updateIntervalSecs` | `double?` | How often (in seconds) the plugin should emit playback position updates. |
| `controlPanelInfoType` | `ControlPanelInfoType?` | What metadata to display in the system control panel. See [ControlPanelInfoType](#controlpanelinfotype). |
| `controlPanelTimebase` | `ControlPanelTimebase?` | Timeline basis used by system media controls. See [ControlPanelTimebase](#controlpaneltimebase). If an unknown serialized value is parsed, it falls back to `chapter`. |

```dart
await reader.audioSetPreferences(AudioPreferences(speed: 1.5, seekInterval: 30));
```

### ControlPanelInfoType

Determines what metadata is shown in the system media controls (lock screen, notifications, CarPlay / Android Auto, etc.). The same enum is also accepted by `TTSPreferences`.

| Value | Description |
|-------|-------------|
| `standard` | Publication title as the primary line, author as the secondary line. |
| `standardWCh` | Like `standard`, but appends the current chapter title to the primary line when known. |
| `chapterTitleAuthor` | Current chapter as the primary line, publication title combined with author as the secondary line. |
| `chapterTitle` | Current chapter as the primary line, publication title as the secondary line. |
| `titleChapter` | Publication title as the primary line, current chapter as the secondary line. |

The exact mapping to "title" vs. "artist" fields is platform-specific (iOS `MPNowPlayingInfoCenter` vs. Android `MediaMetadata`) and may render slightly differently on each system.

### ControlPanelTimebase

Determines whether the system media controls (lock screen, notifications, CarPlay / Android Auto, etc.) use chapter-relative or publication-relative timeline values.

| Value | Description |
|-------|-------------|
| `chapter` | Use chapter-relative timeline values. |
| `fullBook` | Use full-publication timeline values. |

When parsing serialized values, aliases such as `full_book` (any case) are accepted.
