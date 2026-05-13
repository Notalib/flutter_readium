# Changelog

All notable changes to `flutter_readium` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

### Fixed

- `totalProgression` rounding errors that caused the progress value to exceed `1.0`.
- Media-overlay books silently discarding their position on playback end.
- `ReadiumError` serialised as a JSON-safe string across the method channel.
- iOS `TimebasedState` updates emitted even before the first Locator is received.
- iOS dead-thread crash on reader disposal.
- iOS `goToLocator` incorrectly stripping all URI fragments.
- iOS `play(null)` semantics brought into line with Android.
- iOS media-overlay `asTextLocator` producing malformed fragment hrefs.
- iOS publisher-styles flag (`EPUBPreferences.publisherStyles`) now respected.
- Android `goToProgression` time-offset lookup.
- Android `goToProgression` broken when restoring state.
- Android `TTS.play` not starting playback when the player was already paused.
- Android `ReadiumTimebasedState` `duration` and `currentBuffered` incorrect values.
- Android state-restore crash caused by mixing `Serializable` and `Parcelize`.
- Android decorations lost after restoring state.
- `Locator.timestamp` type corrected from `int` to `double`.
- `ReadiumReaderWidget.loadingWidget` parameter made properly functional.

### Changed

- License normalised to BSD-3-Clause across all sub-packages.
- Federated plugin structure introduced: `flutter_readium` + `flutter_readium_platform_interface`.
- Android host activity requirement documented: must extend `FlutterFragmentActivity`.
