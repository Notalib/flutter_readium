# Changelog

All notable changes to `flutter_readium_platform_interface` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Added

- `PDFPreferences` — model for PDF reader display preferences (`scroll: bool?`,
  `readingProgression: PDFReadingProgression?`) with `toJson` / `fromJson` and `copyWith`.
- `PDFReadingProgression` — enum (`ltr` / `rtl`) used by `PDFPreferences`.
- `setPDFPreferences(PDFPreferences)` — new method on the platform interface and
  `MethodChannelFlutterReadium`; routes through the existing `setPreferences` method-channel
  call, dispatched by format on the native side.

## [0.0.1] - 2025-05-12

### Added

- `FlutterReadiumPlatform` — abstract platform interface class that all platform implementations
  must extend.
- `MethodChannelFlutterReadium` — default `MethodChannel` / `EventChannel` implementation of the
  platform interface, used by the native plugins.
- **Model classes** (all JSON-serialisable via hand-written `toJson` / `fromJson`):
  - `Publication` — top-level publication container with metadata, reading order, resources,
    table of contents, and page list.
  - `Metadata` — publication metadata including title, authors, language, subject, and
    `numberOfPages`.
  - `Locator` — position identifier within a resource, containing `href`, `type`, `title`,
    `text`, `locations` (progression, position, CSS selector, fragments), and `timestamp`.
  - `Link` — hyperlink to a resource within or outside the publication.
  - `LocalizedString` — internationalised string map keyed by BCP 47 language tags.
  - `EPUBPreferences` — reader display preferences (font, scroll mode, CSS overrides).
  - `AudioPreferences` — audio playback preferences (speed, pitch).
  - `TTSPreferences` — TTS preferences (voice, speed, pitch, language).
  - `ReaderDecoration` — decoration applied to a range within the visual reader.
  - `ReaderDecorationStyle` — style (colour, opacity, border) for a decoration.
  - `ReaderTTSVoice` — TTS voice descriptor with identifier, language, and quality metadata.
  - `ReadiumReaderStatus` — enum of reader lifecycle states (idle, loading, ready, error).
  - `ReadiumTimebasedState` — timebased navigator playback state including current `Locator`,
    `duration`, `currentTime`, `currentBuffered`, and play/pause status.
  - `ReadiumError` — structured error type propagated from native to Dart.
  - `TextSearchResult` — single search hit containing the matching `Locator` and surrounding text.
  - `PageInformation` — page counter snapshot with `currentPage` and `totalPages`.
- `ReadiumException` — Dart exception wrapping a `ReadiumError`.
- `ReaderTTSVoiceUtils` — utility to load and query the bundled Readium voice-data JSON.
