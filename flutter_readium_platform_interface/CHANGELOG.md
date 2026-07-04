# Changelog

All notable changes to `flutter_readium_platform_interface` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Added

- `ReadiumErrorCode` — typed enum for error-event codes with `isFatal` /
  `isInformational` and `category` getters, parsed onto `ReadiumError.codeEnum`
  (raw string `code` kept). Vocabulary documented in
  `docs/api-reference/error-codes.md`.
- Typed getters on `ReadiumError`: `href`, `attempt`, `maxAttempts`,
  `httpStatus`.

### Changed

- **Breaking**: `ReadiumError.data` (freeform string) is replaced by
  `details` (`Map<String, dynamic>?`) carrying structured fields
  `{href, attempt, maxAttempts, httpStatus}`. Legacy string payloads are
  wrapped as `{"message": <string>}`.

## [0.2.0] - 2026-07-02

### Added

- `ImageTapEvent` — model for an EPUB image tap, carrying the publication-relative
  `href`, optional `caption` / `alt`, an on-screen `rect` (`dart:ui` `Rect`), and
  natural `pixelWidth` / `pixelHeight`, with hand-written `toJson` / `fromJson`.
- `getResourceUrl(String href)` — resolves any publication resource (e.g. an image
  link from `ImageTapEvent.href`) to a loadable URL over the method channel: a
  native-cached `file://` URL on iOS/Android, or the served resource URL on Web.
  Throws `PlatformException` when the resource is missing or unreadable. On Web,
  loading the resolved URL as an image requires the server to send
  `Access-Control-Allow-Origin` — a CanvasKit/browser constraint, not fixable
  client-side.
- `Publication.conformsToReadiumDivina` — convenience getter mirroring the existing
  `conformsToReadiumPDF/Ebook/Audiobook` helpers; returns `true` for CBZ comics and other
  image-based publications whose `metadata.conformsTo` includes the DiViNa profile URI.
- `TTSPreferences.pageBreakBehavior` (`PageBreakBehavior?`) — controls how EPUB page-break
  elements are handled during TTS playback. Values: `readAsIs` (default — raw label spoken as-is),
  `prefixLabel` (label rewritten with a localized prefix, e.g. "Page 42"), `skip` (element
  filtered out entirely).

### Changed

- `Publication.containsGuidedNavigation` — and therefore `isAudioBook` — now also returns
  `true` for DiViNa comics that carry a guided-navigation document, not only EPUBs. Guided
  navigation is profile-agnostic; this lets DiViNa narrated comics drive the audio /
  media-overlay path the same way narrated EPUBs do.
- `EPUBPreferences.fontSize` is now clamped to Readium's supported ratio range
  `[0.1, 5.0]` on serialization, logging a warning when an out-of-range value is passed.


## [0.1.1] - 2026-06-26

### Fixed

- `EpubColumnCount` now serializes to Readium's canonical values (`auto`/`1`/`2`) instead of
  `auto`/`one`/`two`, fixing column count not being applied natively. `fromJson` still accepts
  the legacy `one`/`two` strings.

## [0.1.0] - 2026-06-20

### Added

- `ReadiumTimebasedState.totalProgressDuration` — nullable `Duration` for the
  publication-level playback offset derived from
  `currentLocator.locations.totalProgression * publicationDuration`.
- `ReadiumTimebasedState.totalDuration` — nullable `Duration` for the total
  publication duration (sum of all reading-order link durations); `null` when any
  reading-order link is missing a duration.
- `PDFSpread` — enum (`auto` / `never` / `always`) for synthetic dual-page spread on
  PDF publications. iOS only; Android `PdfiumPreferences` does not expose spread.
- `PDFPreferences` — three new iOS-only fields: `offsetFirstPage: bool?`,
  `spread: PDFSpread?`, and `visibleScrollbar: bool?`, with matching `toJson` /
  `fromJson` / `copyWith` / `props` wiring. Ignored on Android and web.
- `MediaType.readiumNarration` — `application/vnd.readium.narration+json`, the
  per-item Sync Narration media-overlay format used by the Readium ts-toolkit (web).
- `TaggedReadiumLog` — `ReadiumLog.tag('Name')` factory creating child loggers named
  `flutter_readium.<Name>`, surfacing the source / area in log records.
- `EPUBPreferences.preventMOColumnBreaks` (`bool`, default `true`) — when `true`,
  prevents paragraph elements from splitting across CSS columns during media-overlay
  playback, keeping audio and visible text in sync on paginated iOS layouts. Set to
  `false` to opt out and preserve the EPUB's original column layout. Has no effect
  outside of media-overlay mode.

### Changed

- `FlutterReadiumPlatform.currentReaderWidget` and `defaultPreferences` are now
  read-only getters for consumers, with `@protected` setters — the active reader widget
  registers itself rather than being assigned directly. Use `setDefaultPreferences` to
  update default preferences.

## [0.0.1] - 2026-06-01

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
- **Page information** — `Locations.page` / `Locations.totalPages` extension getters expose the
  current page and total page count parsed from locator fragments.
- `ReadiumReaderWidgetInterface` — abstract interface that platform-specific reader widget
  implementations extend; consumed by `FlutterReadiumPlatform.currentReaderWidget`.
- `ReadiumException` — Dart exception wrapping a `ReadiumError`.
- `ReaderTTSVoiceUtils` — utility to load and query the bundled Readium voice-data JSON.
