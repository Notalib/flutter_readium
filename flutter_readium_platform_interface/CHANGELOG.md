# Changelog

All notable changes to `flutter_readium_platform_interface` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

## [0.0.1] - 2025-06-01

### Added

- `PDFPreferences` — model for PDF reader display preferences (`layout: PDFLayout?`,
  `readingProgression: PDFReadingProgression?`, `pageSpacing: double?`, `fit: PDFFit?`) with
  `toJson` / `fromJson` and `copyWith`.
- `PDFLayout` — enum (`paginated` / `scrollVertical` / `scrollHorizontal`) used by
  `PDFPreferences`. Unifies iOS's `scroll` + `scrollAxis` and Android's `scrollAxis` into a
  single cross-platform setting.
- `PDFReadingProgression` — enum (`ltr` / `rtl`) used by `PDFPreferences`.
- `PDFFit` — enum (`auto` / `page` / `width`) controlling how PDF pages are fitted in the
  viewport.
- `setPDFPreferences(PDFPreferences)` — new method on the platform interface and
  `MethodChannelFlutterReadium`; routes through the existing `setPreferences` method-channel
  call, dispatched by format on the native side.
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
- **Reader enums**:
  - `DefaultSelectionAction` — system-provided selection menu items (`copy`, `share`, `lookup`,
    `translate`, `selectAll`) that callers can allow or filter out via
    `ReadiumReaderWidget.allowedDefaultActions`.
  - `DecorationStyle` — built-in decoration styles (`highlight`, `underline`) used when
    constructing a `ReaderDecorationStyle`.
  - `LogLevel` — log verbosity (`none`, `error`, `warn`, `info`, `debug`) passed to
    `setLogLevel`.
- `ReadiumReaderWidgetInterface` — abstract interface that platform-specific reader widget
  implementations extend; consumed by `FlutterReadiumPlatform.currentReaderWidget`.
- `ReadiumException` — Dart exception wrapping a `ReadiumError`.
- `ReaderTTSVoiceUtils` — utility to load and query the bundled Readium voice-data JSON.
