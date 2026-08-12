# Changelog

All notable changes to `flutter_readium_platform_interface` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Fixed

- `ReadiumTimebasedState.fromJson()` now tolerates audiobook terminal locators
  that omit `progression` / `totalProgression`, preserving the locator while
  normalizing ended-state progress to `1.0` instead of crashing on Android.

## [0.3.3] - 2026-08-04

## [0.3.2] - 2026-08-03

## [0.3.1] - 2026-07-24

No changes — version bumped to stay in lockstep with `flutter_readium`.

## [0.3.0] - 2026-07-13

### Added

- `ReadiumErrorCode` — typed, cross-platform error-code enum, exposed as
  `ReadiumError.codeEnum`, with `isFatal`, `isInformational`, and `category`
  getters. `ReadiumError` also adds typed `href`, `attempt`, `maxAttempts`,
  and `httpStatus` getters. Vocabulary documented in
  [`docs/api-reference/error-codes.md`](../docs/api-reference/error-codes.md).
- `AudioRecoveryPolicy` — configures the automatic audio-stream recovery loop
  (retry attempts, backoff, stall timeout, and connection timeout); apply via
  `FlutterReadium().setAudioRecoveryPolicy(policy)`. Defaults reproduce prior
  recovery behaviour. Fields and semantics:
  [`docs/api-reference/error-codes.md#audiorecoverypolicy`](../docs/api-reference/error-codes.md#audiorecoverypolicy).

### Changed

- **Breaking**: awaited platform failures now surface a single `ReadiumException`
  shape that wraps `ReadiumError`. The opening-specific Dart exception API
  (`OpeningReadiumException`, `OpeningReadiumExceptionType`,
  `PublicationNotSetReadiumException`, and `OfflineReadiumException`) has been
  removed; catch `ReadiumException` and handle failures via `e.code` /
  `e.codeEnum`.
- **Breaking**: `ReadiumError` is now a value type rather than a Dart `Error`;
  native `stackTrace` is removed. Its freeform `data` payload is replaced by
  an unmodifiable structured `details` map.
  
## [0.2.1] - 2026-07-09

### Fixed

- `Properties.toJson()` emitted the `orientation`, `layout`, `overflow` and `spread`
  presentation hints as raw enum instances instead of their string names, so
  `jsonEncode`-ing a serialized `Publication` threw for fixed-layout (FXL) resources
  (e.g. `Converting object to an encodable object failed: Instance of 'EpubLayout'`).
  They now serialize as strings and round-trip through `fromJson`.

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
