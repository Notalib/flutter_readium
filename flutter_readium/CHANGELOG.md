# Changelog

All notable changes to `flutter_readium` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Added

- **Text selection callback** — `ReadiumReaderWidget.onTextSelected` fires a
  `TextSelectionEvent` (locator + selected text) when the user selects text in the reader.
  Supported on iOS, Android, and Web.
- **Selection actions** — `ReadiumReaderWidget.selectionActions` configures native context menu
  items (up to 5 on iOS) shown on text selection. Tapping an action fires
  `ReadiumReaderWidget.onSelectionAction` with a `SelectionActionEvent`.
- **Decoration interaction** — `ReadiumReaderWidget.onDecorationInteraction` fires a
  `DecorationInteractionEvent` when the user taps an existing decoration/highlight.
  Supported on iOS and Android.
- **Allowed default actions** — `ReadiumReaderWidget.allowedDefaultActions` controls which
  system-provided selection menu items (Copy, Share, Look Up, Translate, Select All) are
  shown. Pass `null` for all defaults, or a specific `Set<DefaultSelectionAction>` to filter.
  iOS supports `copy`, `share`, `lookup`, `translate`; Android supports `copy`, `share`,
  `selectAll`. Unsupported values for a platform are silently ignored.

- **PDF reading** — `ReadiumReaderWidget` now opens PDF publications on iOS (PDFKit via
  `PDFNavigatorViewController` from swift-toolkit) and Android (PDFium via
  `PdfiumNavigatorFragment` from kotlin-toolkit). PDF is not supported on Web.
- **PDF preferences** — `FlutterReadium.setPDFPreferences(PDFPreferences)` applies runtime
  display settings (`scroll`, `readingProgression`) to the active PDF navigator.
- **PDF TOC enrichment** — `onTextLocatorChanged` events for PDF publications now include
  `title` (chapter name) and `locations.otherLocations["tocHref"]` derived from `#page=N`
  TOC fragments, matching the existing EPUB enrichment behaviour.

## [0.0.1] - 2025-05-12

### Added

- **Core reader API** — `FlutterReadium` singleton providing `openPublication`, `closePublication`,
  `loadPublication`, `goToLocator`, `goToProgression`, `goForward`, `goBackward`.
- **EPUB reader widget** — `ReadiumReaderWidget` renders EPUB and WebPub content via a native
  platform view (iOS/macOS/Android) or a WebView (web).
- **EPUB preferences** — `EPUBPreferences` with font family, font size, theme, scroll mode,
  line height, word spacing, letter spacing, paragraph spacing, text alignment, column count,
  publisher styles, vertical writing, custom CSS properties and first-element margin.
- **TTS (text-to-speech)** — `ttsEnable`, `ttsSetPreferences`, `ttsSetVoice`,
  `ttsGetAvailableVoices` with voice metadata loaded from the Readium speech voice-data registry.
  TTS decoration styles are configurable via `setDecorationStyle`.
- **Audio / MediaOverlay playback** — `audioEnable`, `audioSetPreferences`, `audioSeekBy`,
  `play`, `pause`, `resume`, `stop`, `next`, `previous` for pre-recorded audio publications
  and MediaOverlay synchronized narration.
- **Decorations** — `applyDecorations` lets callers add highlights, underlines, and custom
  decoration styles to the visual reader.
- **Search** — `searchInPublication` returns a list of `TextSearchResult` matching a query string.
- **Navigation helpers** — `skipToNextTOC` / `skipToPreviousTOC` walk the publication's
  table of contents; `toPhysicalPageIndex` and `goByLink` navigate by page-list entry or link.
- **Event streams** — `onReaderStatusChanged`, `onTextLocatorChanged`,
  `onTimebasedPlayerStateChanged`, `onErrorEvent` expose real-time reader state as Dart streams.
- **Platform support** — iOS (swift-toolkit 3.7.0), macOS (same), Android (kotlin-toolkit 3.1.2),
  Web (TypeScript webpack bundle using @readium/navigator).
- **Custom HTTP headers** — `setCustomHeaders` forwards headers to the native HTTP layer.
- **Log level control** — `setLogLevel` configures the plugin's internal logging verbosity.
- **Page information** — `PageInformation` model exposes `currentPage` and `totalPages` for
  publications that include a page list.
- **Progress slider** support in the example app via a slider bound to `totalProgression`.
