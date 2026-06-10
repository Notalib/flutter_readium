# Changelog

All notable changes to `flutter_readium` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

Brings the Web platform up to feature parity with iOS / Android (audio,
Media Overlay, TTS, Guided Navigation, decorations), plus a handful of
supporting cross-platform additions.

### Fixed

- **iOS: early reader events are no longer dropped** — the `text-locator` and
  `reader-status` event channels now buffer the most-recent event on the native
  side when Dart has not yet attached a listener.  The buffer is flushed
  immediately when `onListen` fires, eliminating the race between the EPUB
  platform-view initialisation and the asynchronous stream-subscription
  handshake.  Buffers are cleared on `closePublication()` so stale events from
  a closed publication are never replayed to the next subscriber.

### Added

- **Web: Audio Navigator** — audiobook publications now play on web. `audioEnable`,
  `play`, `pause`, `resume`, `stop`, `next`, `previous`, `audioSetPreferences` are all
  wired up via the upstream `AudioNavigator` (ts-toolkit 2.4.0+). Playback state
  (offset, duration, locator) streams through `onTimebasedPlayerStateChanged`, matching
  the iOS / Android contract.
- **Web: Media Overlay (Sync Narration)** — EPUBs with embedded Sync Narration JSON
  alternates (`application/vnd.readium.narration+json`) can now play their synchronized
  narration. `audioEnable()` parses the narration, builds a synthetic audio reading
  order, and drives `AudioNavigator`; audio time is mapped back to text locators so
  `onTextLocatorChanged` emits text-href locators as narration advances (matching
  iOS / Android `reachedLocator`). Enabling audio resumes from the visual reader's
  current position, `goToLocator` and ToC / bookmark taps seek the audio to the matching
  narration item, and `audioSeekBy` is wired up via `AudioNavigator.jump()`.
- **Web: TTS (text-to-speech)** — `ttsEnable`, `ttsGetAvailableVoices`, `ttsSetVoice`,
  `ttsSetPreferences` are implemented on web using the browser's `SpeechSynthesis` API
  and `@readium/shared`'s `PublicationContentIterator` + `HTMLResourceContentIterator`
  for paragraph-level text extraction. Playback state streams through
  `onTimebasedPlayerStateChanged` and position bookmarks through `onTextLocatorChanged`.
  Voice gender / quality is enriched via the bundled `voices.json` from
  https://readium.org/speech/. `play`, `pause`, `resume`, `stop`, `next`, `previous`
  dispatch to the TTS engine when active, falling back to `AudioNavigator` otherwise.
- **Web: Guided Navigation support** — the web platform now detects EPUBs carrying
  `application/guided-navigation+json` (publication-level link or reading-order
  alternate) and plays them through the Media Overlay pipeline, mirroring iOS / Android.
  When both Guided Navigation and Sync Narration are present, Guided Navigation takes
  precedence — matching native behaviour. Playback keeps the visual reader scrolled in
  sync.
- **Web: comic / FXL publication support** — fixed-layout (Nota comic) publications
  now render on web.
- **Web: `goToProgression`** — navigates to an absolute progression (0.0–1.0) on web.
  Supports EPUB (position-list lookup), audiobook (seek to `progression × duration`),
  and Media Overlay content types.
- **Web: `audioSeekBy`** — `audioSeekBy(Duration offset)` is implemented for audiobook
  and Media Overlay playback via `AudioNavigator.jump()`.
- **Web: `onErrorEvent` stream implemented** — subscribing to
  `FlutterReadium().onErrorEvent` on web no longer returns an empty stream. A broadcast
  `StreamController<ReadiumError>` now backs the stream; `openPublication` failures in
  the JS bundle are forwarded to Dart via an `onErrorCallback` window setter. Pure
  audiobook paths register the same callback via `_AudiobookCallbacks`.
- **Web: ToC enrichment for media-overlay items** — Sync Narration and Guided
  Navigation items are enriched with `tocTitle` / `tocHref` derived from the
  publication's table of contents, matching `enrichOverlaysWithToc` on iOS / Android.
- **Web: `onTextLocatorChanged` locators now carry `tocHref`** — the EPUB navigator
  enriches each emitted locator with the current chapter's ToC href, matching the
  iOS / Android contract and unblocking chapter-skip features on the consumer side.
- **Web: TTS locators now carry `tocHref`** — `Locator.locations.tocHref` is now
  populated on every locator emitted during TTS playback (utterance-start and
  word-boundary events), so chapter-aware features work during TTS on web — matching
  the existing behaviour for visual navigation and audiobook / media-overlay playback.
- **Web: reading-order item duration propagated to media-overlay items** — the parent
  reading-order link's declared `duration` (when present) is carried on each item and
  used as the authoritative fallback for the synthetic audio Link's duration, replacing
  the cue-sum-only computation that underestimated total length when cues left gaps.
- **Web: `scrollPaddingLeft` / `scrollPaddingRight` EPUB preferences** — new fields in
  ts-toolkit 2.5.x are now passed through to the navigator.
- **Web: structured console logging** — all web TS modules now log through a tagged
  logger (`[Readium/<Module>] LEVEL: message`) with runtime level control. `setLogLevel`
  now propagates to the JS bundle so web logging verbosity is controlled from Dart
  alongside the native platforms.
- **Web: parser unit tests** — a Jest suite for the Guided Navigation parser (JSON-layer
  parsing + sliding-window ToC enrichment). Run with `npm test` from the
  `flutter_readium` package.
- **Dart: tagged logging (`TaggedReadiumLog`)** — new `ReadiumLog.tag('Name')` factory
  creates child loggers named `flutter_readium.<Name>`, surfacing the source / area in
  log records (e.g. `[INFO] flutter_readium.WebPlugin: ...`).
- **PDF preferences: three new iOS-only fields** — `offsetFirstPage: bool?`,
  `spread: PDFSpread?` (new enum: `auto` / `never` / `always`), and
  `visibleScrollbar: bool?`. These map to the matching properties on the iOS
  `PDFNavigatorViewController.Preferences`. Android `PdfiumPreferences` does not expose
  these fields; they are silently ignored on Android and web.
- **`totalProgression` for EPUB and audio navigators (web)** — computed and surfaced for
  the progress slider on web.

### Changed

- **Web: ts-toolkit version bump** — `@readium/navigator` `^2.2.4` → `^2.5.5`,
  `@readium/navigator-html-injectables` `^2.2.1` → `^2.4.2`,
  `@readium/shared` `^2.1.1` → `^2.2.0`. Picks up FXL `positionChanged` reliability fix
  (navigator #218), vertical / RTL writing-mode support, Readium CSS v2.0.0, and
  content-protection infrastructure.
- **Web Decorator API** — `applyDecorations` and `setDecorationStyle` are now functional
  on web. `applyDecorations` replaces a group's decorations by sending a `"clear"` then
  an `"add"` per decoration via the upstream `@readium/navigator-html-injectables`
  FrameComms `"decorate"` command. The `highlight` (filled box) and `underline`
  (border-bottom) styles are both supported.
- **Web underline-style decorations** — `DecorationStyle.underline` renders as a
  border-bottom in the tint colour rather than a filled box, routed to a separate
  upstream group (`<group>__underline`) with an injected stylesheet + `MutationObserver`
  per iframe. The same distinction works in the CSS Custom Highlight API path (modern
  Chrome) via a paired sibling `<style>` whose `::highlight()` rule wins by cascade order.
- **Web: EPUB preferences mapping cleanup** — `epubPreferences.ts` now mirrors the Dart
  `EPUBPreferences` shape (one preference per Dart field), with documented conversions:
  `columnCount` enum (auto/one/two) → `number | null`, `imageFilter` enum (darken/invert)
  → `darkenFilter` / `invertFilter`, and `fontSize` divided by 100 to match the iOS
  plugin (Dart `120` → web `1.2`). Dart fields the web navigator can't honor
  (`publisherStyles`, `readingProgression`, `spread`, `typeScale`, `verticalText`,
  `language`, `blackAndWhiteComicMode`, `firstElementTopMargin`) are dropped with inline
  rationale.
- **Web: content-protection, peripheral, and context-menu listener stubs** — new
  required listener fields from ts-toolkit 2.3.0 are now present on both EPUB and WebPub
  navigator configurations.
- **Docs: removed `EpubThemeType` / `theme` preference** — the `theme` field referenced
  in `docs/api-reference/preferences.md` and `docs/guides/preferences.md` was never
  implemented; the docs now show how to achieve light / dark / sepia by setting
  `backgroundColor` and `textColor` directly.

### Fixed

These are fixes to behaviour that shipped in `0.0.1` — chiefly the existing web EPUB
visual reader and cross-platform serialization. (Bugs introduced and resolved while
building the new web audio / TTS / Media Overlay features are not listed separately;
their net effect is the `Added` entries above.)

- **Web: `setEPUBPreferences` no longer wipes existing preferences** — the converter now
  emits only fields the Dart caller explicitly set, leaving prior preferences untouched
  on merge. Previously every unset field was sent as `null`, which the navigator's
  `merging()` does not skip (only `undefined`), so a partial update reset everything.
- **Web: `onTextLocatorChanged` no longer floods consumers during scroll** — text-locator
  events are trailing-edge debounced at 250 ms, matching the per-page cadence of the
  iOS / Android plugins (the ts-toolkit emits ~60 events/sec in scroll mode).
- **Web: EPUB navigation (`goTo`, `goForward`, `goBackward`, ToC links) now works** —
  `ReadiumReader.goTo` searches `readingOrder` before `resources` (ToC chapter links
  point into reading order, so the previous resources-only lookup always failed), and the
  JS bridge now implements the progression-aware navigation methods `goForward` /
  `goBackward` call (previously errored with `is not a function`).
- **Web: nested ToC entries are no longer dropped** — `flattenToc` treated
  `@readium/shared`'s `Links` as a plain array, silently discarding nested children;
  it now uses the `Links` API.
- **`LocalizedString` translation-map parsing** and **`Properties.toJson` `page` key**
  serialization corrected (affects all platforms).
- **iOS: `applyDecorations` and `setEPUBPreferences` no longer hang when awaited** — the
  EPUB reader view's native handlers now return a method-channel result on success
  (matching the PDF reader view); previously they never completed, so awaiting these
  methods could hang forever.

## [0.0.1] - 2025-06-01

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
- **Decoration styles** — `DecorationStyle` has two modes: `highlight`
  (filled rectangle behind text — default) and `underline` (border-bottom in tint
  colour). Both are supported on iOS and Android.
- **Text selection callback** — `ReadiumReaderWidget.onTextSelected` fires a
  `TextSelectionEvent` (locator + selected text) when the user selects text in the reader.
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
- **PDF reading** — `ReadiumReaderWidget` opens PDF publications on iOS (PDFKit via
  `PDFNavigatorViewController` from swift-toolkit) and Android (PDFium via
  `PdfiumNavigatorFragment` from kotlin-toolkit). PDF is not supported on Web.
- **PDF preferences** — `FlutterReadium.setPDFPreferences(PDFPreferences)` applies runtime
  display settings (`layout`, `readingProgression`, `pageSpacing`, `fit`) to the active PDF
  navigator. `PDFLayout` unifies iOS's `scroll` + `scrollAxis` and Android's `scrollAxis` into
  one cross-platform setting (`paginated`, `scrollVertical`, `scrollHorizontal`); `PDFFit`
  controls page fitting (`auto`, `page`, `width`).
- **PDF TOC enrichment** — `onTextLocatorChanged` events for PDF publications include
  `title` (chapter name) and `locations.otherLocations["tocHref"]` derived from `#page=N`
  TOC fragments, matching the existing EPUB enrichment behaviour.
- **Search** — `searchInPublication` returns a list of `TextSearchResult` matching a query string.
- **Navigation helpers** — `skipToNextTOC` / `skipToPreviousTOC` walk the publication's
  table of contents; `toPhysicalPageIndex` and `goByLink` navigate by page-list entry or link.
- **Event streams** — `onReaderStatusChanged`, `onTextLocatorChanged`,
  `onTimebasedPlayerStateChanged`, `onErrorEvent` expose real-time reader state as Dart streams.
- **Platform support** — iOS (swift-toolkit 3.7.0), macOS (same), Android (kotlin-toolkit 3.1.2),
  Web (TypeScript webpack bundle using @readium/navigator).
- **Custom HTTP headers** — `setCustomHeaders` forwards headers to the native HTTP layer.
- **Log level control** — `setLogLevel` configures the plugin's internal logging verbosity.
- **Page information** — `Locations.page` and `Locations.totalPages` extension getters expose
  the current page and total page count (parsed from locator fragments) for publications that
  include a page list.
- **Progress slider** support in the example app via a slider bound to `totalProgression`.
