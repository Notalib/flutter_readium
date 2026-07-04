# Changelog

All notable changes to `flutter_readium` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### Added

- **Audio streaming error events + connection recovery** — failures while
  streaming remote audiobook resources (network loss, HTTP/auth errors) are
  now reported on the error stream and no longer silently swallowed. Transient
  failures trigger automatic recovery (3 attempts, exponential backoff) with an
  `AudioStreamRetry` event per attempt while the timebased state stays
  `loading`; terminal failures emit a coded event
  (`AudioStreamAuthError` for HTTP 401/403, `AudioStreamHTTPError` for other
  4xx, `AudioStreamNetworkError`, `AudioStreamError`, or `AudioStreamFailed`
  when retries are exhausted) together with `TimebasedState.failure`, after
  which calling `play()` retries from the last position. Supported on iOS,
  Android, and Web. On Web, browsers do not expose HTTP status codes for
  media loads, so a short diagnostic fetch probes the failing resource to
  classify auth/HTTP errors; when the probe is inconclusive they surface as
  `AudioStreamNetworkError` / `AudioStreamError` instead.

### Fixed

- Android: audio playback failures previously emitted a generic error event
  with no failure classification and no way to resume; they now use the coded
  events above and support retry via `play()`.

## [0.2.0] - 2026-07-02

### Added

- **EPUB image tap** — tapping an image in an EPUB now fires `onImageTapped`
  with an `ImageTapEvent` carrying the publication-relative `href`, optional
  `alt` / `caption`, on-screen `rect`, and pixel dimensions. Detection runs on
  iOS, Android, and Web. Android and Web suppress image-tap events for DiViNa publications
  and Nota comic page images so narrated comics keep their panel navigation behavior.
- **`getResourceUrl(href)`** — new API on `FlutterReadium` and the underlying
  platform interface that resolves any manifest resource to a loadable URL —
  a native-cached `file://` URL on iOS/Android, or the served resource URL on
  Web — plus a companion `FlutterReadium.imageProvider(href)` that plugs into
  Flutter's image pipeline for lazy display. Implemented on iOS, Android, and Web.
  On Web, displaying the resolved URL requires the resource's server to send
  `Access-Control-Allow-Origin` — a CanvasKit/browser constraint, not fixable
  client-side (see `docs/troubleshooting.md`). iOS/Android are unaffected.
- **Narration sync state & manual mode (iOS, Android, Web)** — a new
  `FlutterReadium.onNarrationSyncChanged` stream (`Stream<bool>`: `true` = following narration,
  `false` = manual mode) and `FlutterReadium.setNarrationSyncEnabled(bool)`. While Media Overlay or
  TTS narration is driving the reader, manually turning the page (swipe, edge-tap, or
  next/previous) now enters **manual mode**: audio keeps playing while the reader stops
  auto-following cues, and `onNarrationSyncChanged` emits `false` (e.g. to show a "Re-sync"
  control). Call `setNarrationSyncEnabled(true)` to snap the reader back to the current narration
  position. An explicit jump (`goToLocator` to a TOC entry, bookmark, or search result) instead
  re-seeks narration to the new location, keeping audio and reader together.
- **Comic panel pan/zoom during narration (iOS, Android)** — Nota EPUB+MediaOverlay comics now
  pan and zoom to the active panel as narration plays on native platforms, matching the existing
  web behaviour. A manual pinch-zoom in the EPUB webview enters the same manual mode as a page
  swipe, emitting `onNarrationSyncChanged(false)`; `setNarrationSyncEnabled(true)` re-pans to the
  current narrated panel.
- **Comic explore mode** — Nota MO comics now open directly to the comic page view (no EPUB
  chrome) and accept pinch-zoom for free exploration before narration is started. When
  narration begins, the view transitions automatically to panel-by-panel mode — no Re-sync
  action needed. Stopping narration snaps the comic back to the full-page view instantly.

### Changed

- **`TTSPreferences.pageBreakBehavior`** — controls how EPUB page-break elements (DAISY/Nordic
  EPUB3 `epub:type="pagebreak"`) are handled during TTS. Accepts a `PageBreakBehavior` enum:
  `readAsIs` (default — raw label text spoken unchanged), `prefixLabel` (label rewritten with a
  localized prefix, e.g. "Page 42" / "side 42"; supports English, Danish, Swedish, Norwegian,
  Icelandic; falls back to the raw label otherwise), `skip` (element filtered out entirely).
  Replaces the previous `skipPageBreaks` bool.
- **`EPUBPreferences.disableSynchronization` is deprecated** in favour of the runtime
  `FlutterReadium.setNarrationSyncEnabled(bool)` / `onNarrationSyncChanged`. The preference still
  works and now seeds the unified narration-sync state when a publication is opened.

### Fixed

- **iOS media-overlay playback crashes on malformed sync-narration data** — starting playback in a
  publication with a reversed or non-finite audio time fragment (`t=start,end` where `end < start`)
  no longer traps with `Range requires lowerBound <= upperBound`, and a `narration` block with no
  valid audio/text pairs no longer crashes navigator setup. Such items now degrade gracefully.

## [0.1.1] - 2026-06-26

### Changed (breaking)

- **`EPUBPreferences.fontSize` is now a `double` ratio** (`1.0` = default, `1.5` = 150%)
  instead of a percentage `int`. Divide existing values by 100 to migrate
  (`fontSize: 130` → `fontSize: 1.3`). This fixes Android font-size having no
  visible effect ([#140](https://github.com/Notalib/flutter_readium/issues/140)) and aligns
  the API with Readium's own `EpubPreferences.fontSize`.
- **Web `stop()` now tears down the active audio/TTS navigator**, matching iOS and Android.
  Call `audioEnable()` or `ttsEnable()` again before resuming audiobook, Media Overlay,
  Guided Navigation, or TTS playback after `stop()`.

### Added

- **CBZ comic support (iOS, Android, Web)** — CBZ archives (Comic Book ZIP) now open and render.
  Pages are displayed one at a time; swipe/tap navigates between pages and `goToLocator` restores
  saved positions. On iOS/Android the existing `blackAndWhiteComicMode` preference in
  `ReaderEpubPreferences` applies the grayscale filter to CBZ pages as well.
- **DiViNa narrated-comic support (iOS, Android, Web)** — DiViNa publications (`profiles/divina`)
  that carry a Guided Navigation document open as comics with page-synced audio narration. Page
  images render (via the fixed-layout path on iOS/Android; via a plugin-side image navigator on Web,
  since ts-toolkit ships no DiViNa navigator), and `audioEnable` / `play` drive page-synced audio
  from the guided-navigation document. Panel-level zoom is not yet implemented on any platform (the
  segments' `xywh` / `imgref` regions are carried in the asset for that follow-up).
- **Web comic navigation** — DiViNa/CBZ publications page one image at a time, emit page locators
  (`onPageChanged`), and support `goToLocator` / `goToProgression`.

### Fixed

- **`EPUBPreferences.columnCount` (`one`/`two`) not applied** — the serialized value diverged
  from Readium's canonical `ColumnCount` (`auto`/`1`/`2`), so Android threw a
  `PlatformException` and iOS silently ignored the setting when starting playback. The shared
  Dart serialization now matches the native toolkits; column count is applied on all platforms.
- **iOS: possible crash (`Index out of range`) when enabling audio / starting playback** on
  media-overlay books and comics, caused by an unchecked reading-order index in
  locator resolution. Out-of-range positions now degrade gracefully instead of trapping.
- **iOS + Web: synchronization catch-up after re-enable** — when
  `EPUBPreferences.disableSynchronization` is turned back off (`true -> false`),
  the visual EPUB navigator now jumps to the last sync locator that was reached
  while synchronization was disabled, matching Android behavior.
- **iOS: Media Overlay clips that span a CSS column boundary no longer desync** — in
  paginated mode, a paragraph straddling two columns would start audio on the first
  column but continue playing through text visible only on the second column. When
  media-overlay playback is active, a `break-inside: avoid` CSS rule is now injected
  so each paragraph stays whole on one page, keeping audio and visible text in sync.
  Controlled by `EPUBPreferences.preventMOColumnBreaks` (default `true`; set to
  `false` to opt out and restore the original layout).
- **Android + Web: Media Overlay clips that span a CSS column boundary no longer desync** — same fix
  as iOS above, now applied to Android and Web via the shared `flutterReadium` helper-script bundle.
- **iOS: TTS no longer snaps back to the previous page mid-sentence** — when a spoken sentence
  crossed a paginated page boundary, the reader correctly advanced to page N+1 for the word being
  spoken but then flickered back to page N on each subsequent word. The cause was a double-assignment
  to the `@Published playingUtterance` property (raw locator, then position mutation), which defeated
  `removeDuplicates()` and fired the page-sync on every word update instead of only on utterance
  changes.
- **Web: Improved error-handling** - `ttsEnable`, `audioEnable`, and `ttsGetAvailableVoices` failures are
  now caught and `.stack` is now included in `PlatformException.message`.
- **iOS: early reader events are no longer dropped** — the `text-locator` and
  `reader-status` event channels now buffer the most-recent event on the native
  side when Dart has not yet attached a listener.  The buffer is flushed
  immediately when `onListen` fires.

---

## [0.1.0] - 2026-06-20

Brings the Web platform up to feature parity with iOS / Android (audio,
Media Overlay, TTS, Guided Navigation, decorations), plus a handful of
supporting cross-platform additions.
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
- **`totalProgressDuration` on timebased playback state** — `onTimebasedPlayerStateChanged`
  now includes a publication-level elapsed duration (`ReadiumTimebasedState.totalProgressDuration`)
  computed from `currentLocator.locations.totalProgression` and publication duration when available.
- **`totalDuration` on timebased playback state** — `onTimebasedPlayerStateChanged`
  now includes the total publication duration (`ReadiumTimebasedState.totalDuration`),
  the sum of all reading-order link durations; `null` when any link is missing a duration.
- **`DecorationStyle.spotlight`** — new decoration style that dims everything outside
  the decorated range and (optionally) renders the tint inside it. Implemented across
  Dart API, iOS (`box-shadow` + body dim), Android (`box-shadow` + body dim), and web
  (`body.flutter-readium-spotlight` gates a body-wide dim; a per-group `::highlight()`
  restore rule keeps the spotlit range readable, and the caller-supplied tint colours
  the range's fill). Pass a non-transparent tint for "dim outside + tinted fill"; pass
  a transparent tint for "pure dim outside".
- **`DecorationStyle.ruler`** — new decoration style that renders a typoscope /
  reading mask: two full-viewport-width dim bands sit above and below the decorated
  range, leaving the range itself clear. Best suited to scrolled layouts. Implemented
  on the Dart API and on web (geometry-driven from the resolved range element, so it
  works in both the CSS Custom Highlight API path and the DOM-fallback path).
- **`ReaderDecorationStyle.isActive`** — new `bool` field (default `false`) that
  renders the decoration in a visually distinct "active" state to mark the
  currently-focused annotation. Maps to the upstream
  `Decoration.Style.HighlightConfig.isActive` on iOS and
  `Decoration.Style.Highlight/Underline.isActive` on Android; surfaces on web for the
  highlight / underline / spotlight paths.

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

These are fixes to behaviour that shipped in `0.0.1` — chiefly iOS playback / locator
positioning, the existing web EPUB visual reader, and cross-platform serialization. (Bugs
introduced and resolved while building the new web audio / TTS / Media Overlay features are
not listed separately; their net effect is the `Added` entries above.)

- **iOS: media-overlay books now resume at the saved in-chapter position** — reopening a
  sync-narration book restored the *top of the chapter* instead of where you left off (it only
  snapped to the right place once playback started). swift-toolkit's reflowable navigator positions
  via `fragments.first` and ignores `cssSelector`, where the media-overlay locator's DOM anchor was
  stored; the locator's DOM anchor is now promoted into `fragments.first` for the iOS visual
  navigator. See `docs/parity/locator-field-priority.md`.
- **iOS: TTS no longer snaps back to the previous page mid-sentence** — when a spoken sentence
  crossed a paginated page boundary, the reader correctly advanced to page N+1 for the word being
  spoken but then flickered back to page N on each subsequent word. The cause was a double-assignment
  to the `@Published playingUtterance` property (raw locator, then position mutation), which defeated
  `removeDuplicates()` and fired the page-sync on every word update instead of only on utterance
  changes.
- **iOS: early reader events are no longer dropped** — the `text-locator` and
  `reader-status` event channels now buffer the most-recent event on the native
  side when Dart has not yet attached a listener.  The buffer is flushed
  immediately when `onListen` fires.
- **Web: improved error-handling** — `ttsEnable`, `audioEnable`, and `ttsGetAvailableVoices`
  failures are now caught and `.stack` is now included in `PlatformException.message`.
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
- **Web: `WebPubNavigator` now debounces `onTextLocatorChanged` during scroll** —
  matches the existing EPUB debounce. The WebPub navigator was emitting
  position-changed events at rAF rate (~60 Hz), flooding the Dart-side text-locator
  stream with redundant updates.
- **Web: spotlight decoration now honours its tint and dims reliably on EPUB-profile
  publications** — the spotlight CSS no longer strips the caller-supplied tint (it
  used to force `background-color: transparent !important`, silently dropping any
  fill colour), and the body-wide dim selector is now specific enough to beat the
  ReadiumCSS `customColors_pref.css` user-text-colour rule that previously won the
  cascade on EPUB-profile publications.

---
## [0.0.1] - 2026-06-01

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
