# Changelog

All notable changes to `flutter_readium` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Added (platform interface)

- **Web: `onErrorEvent` stream implemented** — subscribing to
  `FlutterReadium().onErrorEvent` on web no longer returns an empty stream.
  A broadcast `StreamController<ReadiumError>` now backs the stream;
  `openPublication` failures in the JS bundle are forwarded to Dart via an
  `onErrorCallback` window setter. Pure audiobook paths register the same
  callback via `_AudiobookCallbacks`.

### Added (platform interface) — PDF preferences

- **`PDFPreferences`: three new iOS-only fields** — `offsetFirstPage: bool?`,
  `spread: PDFSpread?` (new enum: `auto` / `never` / `always`), and
  `visibleScrollbar: bool?`. These map to the matching properties in the iOS
  `PDFNavigatorViewController.Preferences` struct. Android
  `PdfiumPreferences` does not expose these fields; they are silently ignored
  on Android and web.

### Changed

- **Docs: removed `EpubThemeType` / `theme` preference** — the `theme` field
  referenced in `docs/api-reference/preferences.md` and
  `docs/guides/preferences.md` was never implemented; the docs now show how to
  achieve light / dark / sepia by setting `backgroundColor` and `textColor`
  directly.

### Added

- **Web: Guided Navigation support** — the web platform now detects EPUBs
  carrying `application/guided-navigation+json` (either as a publication-level
  link or as a reading-order alternate) and plays them through the existing
  Media Overlay pipeline, mirroring the iOS / Android implementations. When
  both Guided Navigation and Sync Narration are present, Guided Navigation
  takes precedence — matching native behaviour.
- **Web: ToC enrichment for media-overlay items** — Sync Narration and
  Guided Navigation items are now enriched with `tocTitle` / `tocHref`
  derived from the publication's table of contents, matching the
  `enrichOverlaysWithToc` behaviour already shipped on iOS / Android. This
  surfaces chapter titles on emitted state locators during audio playback.
- **Web: reading-order item duration propagated to media-overlay items** —
  the parent reading-order link's declared `duration` (when present) is now
  carried on each item and used as the authoritative fallback for the
  synthetic audio Link's duration, replacing the cue-sum-only computation
  that underestimated total length when cues left gaps.
- **Web: parser unit tests** — added a Jest test suite for the Guided
  Navigation parser (JSON-layer parsing + sliding-window ToC enrichment).
  Run with `npm test` from the `flutter_readium` package.
- **Web: structured console logging** — all web TS modules now log through a
  tagged logger (`[Readium/<Module>] LEVEL: message`) with runtime level control.
  The `setLogLevel` interface method now propagates to the JS bundle so web
  logging verbosity is controlled from Dart alongside the native platforms.
- **Dart: tagged logging (`TaggedReadiumLog`)** — new `ReadiumLog.tag('Name')`
  factory creates child loggers named `flutter_readium.<Name>`, surfacing the
  source/area in log records (e.g. `[INFO] flutter_readium.WebPlugin: ...`).

### Fixed

- **Example: decoration style selectors support "Off" (no decoration)** — the Utterance
  and Range selectors in the EPUB settings panel now include an "Off" option that disables
  that decoration slot entirely (passes `null` to `setDecorationStyle`).

- **Web: ToC tap now seeks audio (Media Overlay) when the fragment lacks a matching narration item** —
  `textLocatorToAudioLocator` only matched when the locator's fragment/cssSelector exactly
  corresponded to a SyncNarrationItem `textId`; ToC entries that pointed at section headings
  with no sync data (e.g. `chap1.xhtml#title`) silently returned `undefined`, so `goTo` updated
  the visual reader but left the audio playing where it was. Now falls back to the first
  Sync Narration item in the matching resource (mirroring the iOS/Android `firstNotNullOfOrNull`
  / `findItemFromLocator` "no fragments + HTML → first item by href" path) and logs a warning
  so unmatched fragments remain discoverable in the console.

- **Web: `audioEnable` now resumes at the visual reader's current position** — when Dart
  passes no `fromLocator`, the web `ReadiumReader.audioEnable` falls back to the EPUB
  navigator's current locator (both on fresh MediaOverlay init and on re-enable). This
  mirrors Android's `initialLocator ?: epubNavigator?.currentLocator?.value` fallback,
  so toggling audio mid-book starts playback from where the user is reading instead of
  the beginning of the book. The example app's Play button now also passes the latest
  visual/timebased locator from `PlayerControlsBloc` instead of the (stale) opening
  locator from `PublicationBloc`.

- **Web: `goToLocator` with audio enabled now maps text locators to the correct audio position** —
  bookmarks and ToC entries pointing at a text paragraph (with a `#id` fragment or progression)
  are resolved to the matching SyncNarrationItem and seek the audio navigator to the right
  time offset, matching iOS and Android MediaOverlay Navigator behaviour. The visual EPUB
  navigator is also scrolled to the same paragraph. The same mapping is applied when
  re-enabling audio (`audioEnable`) or calling `play` with a locator.

- **Web: TTS read-aloud not starting** — extended the `@readium/shared` 2.2.0
  patch to also fix the compiled `dist/` bundles (`index.js` and `index.umd.cjs`).
  The previous patch only modified the `src/` TypeScript file, which webpack
  never consumes (the package's `module`/`main` entries point to `dist/`), so
  the `PublicationContentIterator.loadIteratorAt` bug (missing `return`)
  remained in the shipped bundle and `hasNext()` always returned false.
- **Web: Media Overlay audio playback crash** — fixed "Failed to create new
  Audiobook manifest" error when starting Media Overlay playback. The synthetic
  manifest was built using `JSON.stringify` on class instances (producing invalid
  RWPM JSON); now uses the proper `Manifest.serialize()` / `Link.serialize()` API.
- **Web: Audio does not advance to next track** — two issues fixed: (1)
  AudioNavigator's `autoPlay` preference was hardcoded to `false`, overriding the
  default and preventing auto-advance; now passes `null` so the `true` default
  takes effect. (2) The `trackEnded` listener unconditionally emitted "ended" state
  to Dart on every track boundary, causing the example app's player bloc to close
  the session. Now only emits "ended" on the final track.
- **Web: Audio requires pressing play twice** — `audioEnable` and `play` with a
  `fromLocator` called `go()` to seek without starting playback first. Since the
  navigator wasn't playing, `go()`'s `wasPlaying` check was `false` and it never
  resumed after the seek. Now calls `play()` before `go()` so the play-intent is
  captured and playback resumes automatically after seeking.

### Added

- **Web: structured console logging** — all web TS modules now log through a
  tagged logger (`[Readium/<Module>] LEVEL: message`) with runtime level control.
  The `setLogLevel` interface method now propagates to the JS bundle so web
  logging verbosity is controlled from Dart alongside the native platforms.
- **Dart: tagged logging (`TaggedReadiumLog`)** — new `ReadiumLog.tag('Name')`
  factory creates child loggers named `flutter_readium.<Name>`, surfacing the
  source/area in log records (e.g. `[INFO] flutter_readium.WebPlugin: ...`).
- **Web: `goToProgression` implemented** — navigates to an absolute progression
  (0.0–1.0) on the web platform. Supports EPUB (position-list lookup), audiobook
  (seek to `progression × duration`), and Media Overlay content types.
- **Web: `EPUBPreferences.disableSynchronization` honored** — when set, the web
  TTS engine no longer scrolls the visual navigator on each utterance, matching the
  native (iOS / Android) behaviour. Plumbed through `ReadiumReader.setEPUBPreferences`
  and the new `WebTTSEngine` constructor.
- **Web: TTS (text-to-speech)** — `ttsEnable`, `ttsGetAvailableVoices`, `ttsSetVoice`,
  `ttsSetPreferences` are now implemented on web using the browser's `SpeechSynthesis` API
  and `@readium/shared`'s `PublicationContentIterator` + `HTMLResourceContentIterator` for
  paragraph-level text extraction. Playback state streams through
  `onTimebasedPlayerStateChanged` and position bookmarks through `onTextLocatorChanged`.
  Voice gender/quality is enriched automatically via the bundled `voices.json` from
  https://readium.org/speech/. `play`, `pause`, `resume`, `stop`, `next`, `previous` are
  dispatched to the TTS engine when it is active, falling back to AudioNavigator otherwise.
  Visual word/sentence highlighting is deferred until ts-toolkit PR #209 (Decorator API)
  merges.
- **Web: Media Overlay (Sync Narration)** — EPUBs with embedded Sync Narration JSON
  alternates (`application/vnd.readium.narration+json`) can now play their synchronized
  narration. Calling `audioEnable()` on such a publication parses the narration, builds a
  synthetic audio reading order, and drives `AudioNavigator`. Audio time is mapped back to
  text locators, so `onTextLocatorChanged` emits text-href locators as narration advances
  (matching iOS/Android `reachedLocator` behaviour). `audioSeekBy` is also wired up via
  `AudioNavigator.jump()`.
- **Web: `audioSeekBy`** — `audioSeekBy(Duration offset)` is now implemented on web for
  audiobook and Media Overlay playback via `AudioNavigator.jump(seconds)`.
- **Web: Audio Navigator** — audiobook publications now play on web. `audioEnable`,
  `play`, `pause`, `resume`, `stop`, `next`, `previous`, `audioSetPreferences` are all
  wired up via the upstream `AudioNavigator` (ts-toolkit 2.4.0+). Playback state
  (offset, duration, locator) streams through `onTimebasedPlayerStateChanged`, matching
  the iOS/Android contract.
- **Web: `scrollPaddingLeft` / `scrollPaddingRight` EPUB preferences** — new fields
  added in ts-toolkit 2.5.x are now passed through to the navigator.
- **Web: content-protection, peripheral, and context-menu listener stubs** — new
  required listener fields from ts-toolkit 2.3.0 are now present on both EPUB and
  WebPub navigator configurations.
- **Web: structured console logging** — all web TS modules now log through a
  tagged logger (`[Readium/<Module>] LEVEL: message`) with runtime level control.
  The `setLogLevel` interface method now propagates to the JS bundle so web
  logging verbosity is controlled from Dart alongside the native platforms.
- **Dart: tagged logging (`TaggedReadiumLog`)** — new `ReadiumLog.tag('Name')`
  factory creates child loggers named `flutter_readium.<Name>`, surfacing the
  source/area in log records (e.g. `[INFO] flutter_readium.WebPlugin: ...`).

### Fixed

- **Web: `setEPUBPreferences` no longer wipes existing preferences** — the converter
  now emits only fields the Dart caller explicitly set, leaving the navigator's
  prior preferences untouched on merge. (Previously, building a `new EpubPreferences(...)`
  initialised every field to `null` via the toolkit's `ensure*` guards, and the
  navigator's `merging()` does not skip `null` — only `undefined`. The submit was
  also extracted from `nav.submitPreferences` into a free variable, which stripped
  the `this` binding — that's now a method call.)
- **Web: `goToProgression` and `searchInPublication` no longer throw** — both now have
  dummy implementations on web that log a debug message and return a safe default.
- **Web: `goBackward` / `goForward` no longer error with `is not a function`** — the
  JS-side `ReadiumReader` was missing the progression-aware navigation methods that
  Dart's `JsPublicationChannel` calls.
- **Web: TOC link navigation now works** — `ReadiumReader.goTo` searches `readingOrder`
  before `resources`. Chapter links from the example's TOC page point into reading
  order, so the previous resources-only lookup always failed.
- **Web: `onTextLocatorChanged.locations.tocHref` is populated** — the EPUB navigator
  enriches each emitted locator with the current chapter's TOC href, matching the
  iOS / Android contract. Unblocks chapter-skip features on the consumer side.
- **Web: `onTextLocatorChanged` no longer floods consumers during scroll** — text-locator
  events are now trailing-edge debounced at 250 ms inside the EPUB navigator listener.
  In scroll mode the ts-toolkit emits ~60 events/sec; this matches the per-page cadence
  of the iOS/Android plugins.
- **Example: EPUB Settings popover now dismisses when tapping outside (web)** — the
  default `showModalBottomSheet` barrier sits behind the iframe on Flutter web, so
  taps fell through. The route now provides its own `PointerInterceptor`-backed barrier.
- **Web: opening a Media Overlay (Sync Narration) WebPub no longer throws** — Sync
  Narration detection treated `link.alternates` as a plain array, but `@readium/shared`
  exposes it as a `Links` instance (`.items` array + helper methods). Opening a
  publication with media overlays now uses `Links.findWithMediaType` / `Links.items`
  instead of `.find()`, eliminating `TypeError: alternates.find is not a function`.
  The same Links-vs-array bug was silently dropping nested TOC children in
  `flattenToc`; nested TOC entries are now flattened correctly.
- **Web: TTS read-aloud not starting** — extended the `@readium/shared` 2.2.0
  patch to also fix the compiled `dist/` bundles (`index.js` and `index.umd.cjs`).
  The previous patch only modified the `src/` TypeScript file, which webpack
  never consumes (the package's `module`/`main` entries point to `dist/`), so
  the `PublicationContentIterator.loadIteratorAt` bug (missing `return`)
  remained in the shipped bundle and `hasNext()` always returned false.
- **Web: Media Overlay audio playback crash** — fixed "Failed to create new
  Audiobook manifest" error when starting Media Overlay playback. The synthetic
  manifest was built using `JSON.stringify` on class instances (producing invalid
  RWPM JSON); now uses the proper `Manifest.serialize()` / `Link.serialize()` API.
- **Web: Audio does not advance to next track** — two issues fixed: (1)
  AudioNavigator's `autoPlay` preference was hardcoded to `false`, overriding the
  default and preventing auto-advance; now passes `null` so the `true` default
  takes effect. (2) The `trackEnded` listener unconditionally emitted "ended" state
  to Dart on every track boundary, causing the example app's player bloc to close
  the session. Now only emits "ended" on the final track.
- **Web: Audio requires pressing play twice** — `audioEnable` and `play` with a
  `fromLocator` called `go()` to seek without starting playback first. Since the
  navigator wasn't playing, `go()`'s `wasPlaying` check was `false` and it never
  resumed after the seek. Now calls `play()` before `go()` so the play-intent is
  captured and playback resumes automatically after seeking.

### Changed

- **Web: EPUB preferences mapping cleanup** — `epubPreferences.ts` now mirrors the Dart
  `EPUBPreferences` shape (one preference per Dart field), with documented conversions:
  `columnCount` enum (auto/one/two) → `number | null`, `imageFilter` enum (darken/invert)
  → `darkenFilter` / `invertFilter`, and `fontSize` divided by 100 to match the iOS
  plugin (Dart `120` → web `1.2`). Live updates and initialization now go through the
  same conversion. Dart fields the web navigator can't honor (`publisherStyles`,
  `readingProgression`, `spread`, `typeScale`, `verticalText`, `language`,
  `blackAndWhiteComicMode`, `firstElementTopMargin`) are dropped with inline rationale.
- **Example: EPUB settings popover hides web-unsupported controls** — Reading Direction,
  Publisher Styles, and B&W Comic Mode toggles are now wrapped in `kIsWeb` so they
  only render on native platforms where they actually have an effect.
- **Web: ts-toolkit version bump** — `@readium/navigator` `^2.2.4` → `^2.5.5`,
  `@readium/navigator-html-injectables` `^2.2.1` → `^2.4.2`,
  `@readium/shared` `^2.1.1` → `^2.2.0`. Picks up FXL `positionChanged` reliability
  fix (navigator #218), vertical/RTL writing-mode support, Readium CSS v2.0.0, and
  content-protection infrastructure.
- **Web Decorator API** — `applyDecorations` and `setDecorationStyle` are now
  functional on the web platform. `applyDecorations` replaces a group's decorations
  by sending a `"clear"` then an `"add"` per decoration via the upstream
  `@readium/navigator-html-injectables` FrameComms `"decorate"` command.
  This API reaches into the upstream navigator's private `_cframes` channel, which is
  intentional — `@readium/navigator` v2.2.4 exposes no public decoration surface.
  `setDecorationStyle` stores TTS utterance/range styles for future use; no TTS engine
  is wired up on web yet.
- **Web underline-style decorations** — `DecorationStyle.underline` now renders as a
  border-bottom in the tint colour rather than a filled box. Implementation routes
  underline-style decorations to a separate upstream group (`<group>__underline`) and
  injects a small stylesheet plus a MutationObserver into each EPUB iframe on load to
  override `.readium-highlight` rendering for that group. The same underline distinction
  also works in the CSS Custom Highlight API path (modern Chrome): a head-level
  MutationObserver pairs upstream's per-group `<style id="readium-decoration-N-style">`
  with our pending registrations FIFO and emits a sibling `<style>` whose
  `::highlight(readium-decoration-N) { text-decoration: underline ... }` rule wins
  by cascade order. Bold and box-model styling on `::highlight()` remain impossible
  per the CSS Custom Highlight API spec allowlist.
- **Decoration styles** — `DecorationStyle` has two modes: `highlight`
  (filled rectangle behind text — default) and `underline` (border-bottom in tint
  colour). Both are supported on iOS, Android, and Web.
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
- **EPUB preferences** — `EPUBPreferences` with font family, font size, scroll mode,
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
