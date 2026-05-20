# PDF support — implementation plan

Working document for adding PDF support to `flutter_readium`. Targets iOS + Android only (Web deferred), uses PDFKit on iOS and PDFium on Android, scoped to **visual feature parity with EPUB** in v1 (open + page navigation + locators + selection + decorations-where-supported + preferences + TOC; **no TTS**).

This document is intended to be read by a fresh-context agent. It links into the codebase by file:line and into the upstream Readium toolkits by URL. Keep it up to date as phases land.

---

## Scope decisions (locked in)

| Decision | Choice | Rationale |
|---|---|---|
| Android PDF backend | PDFium (open-source) via `readium-adapter-pdfium` | Free; matches Readium's open default. Caveat: PdfiumAndroid is unmaintained upstream, practical ~40 MB ceiling on large PDFs. PSPDFKit available if needed later. |
| Platforms in v1 | iOS + Android only | Mirrors how the existing native EPUB navigator is wired. macOS may compile-along-for-the-ride from shared Swift sources but is not a target. ts-toolkit has no first-class PDF navigator, so Web is deferred. |
| Feature scope in v1 | Visual parity with EPUB | Open, page nav, locator events, TOC navigation, selection (where the navigator exposes it), preferences. No TTS. Decorations where supported (only EPUB-side at present). |

---

## Upstream pin reference

- **swift-toolkit 3.7.0** — https://github.com/readium/swift-toolkit/tree/3.7.0
- **kotlin-toolkit 3.1.2** — https://github.com/readium/kotlin-toolkit/tree/3.1.2

Do **not** bump these as part of this work.

---

## Key findings from upstream research

### swift-toolkit (iOS)

- PDF support is **already part of the products the plugin pins**: `ReadiumShared` (contains `PDFKitPDFDocumentFactory`), `ReadiumStreamer` (contains `PDFParser`), `ReadiumNavigator` (contains `PDFNavigatorViewController`), `ReadiumAdapterGCDWebServer` (the HTTP server the navigator requires). **No new pod dependency.**
- `PDFNavigatorViewController` conforms to `VisualNavigator, SelectableNavigator, Configurable, Loggable`. It does **not** conform to `DecorableNavigator` in 3.7.0.
- `DefaultPublicationParser` accepts `pdfFactory: PDFDocumentFactory` — pass `DefaultPDFDocumentFactory()`.
- Locator shape: `Locator.locations.position` = 1-based page number, plus `fragments: ["page=N"]`. PDF publication has exactly one entry in `readingOrder`.
- Reference files in upstream test app:
  - https://github.com/readium/swift-toolkit/blob/3.7.0/TestApp/Sources/Reader/PDF/PDFViewController.swift
  - https://github.com/readium/swift-toolkit/blob/3.7.0/TestApp/Sources/Reader/PDF/PDFModule.swift
  - https://github.com/readium/swift-toolkit/blob/3.7.0/TestApp/Sources/App/Readium.swift
  - https://github.com/readium/swift-toolkit/blob/3.7.0/Sources/Navigator/PDF/PDFNavigatorViewController.swift

### kotlin-toolkit (Android)

- Two Gradle modules to add (PDFium choice): `org.readium.kotlin-toolkit:readium-adapter-pdfium:$readium_version`. The PDF *navigator* code lives in the existing `readium-navigator` artifact — no separate `readium-navigator-pdf` artifact.
- Navigator class: `org.readium.r2.navigator.pdf.PdfNavigatorFragment<S, P>`. Conforms to `VisualNavigator, OverflowableNavigator, Configurable<S, P>` (same `VisualNavigator` surface as `EpubNavigatorFragment`). Marked `@ExperimentalReadiumApi`. Constructor is `internal` — must use `PdfNavigatorFactory(publication, pdfEngineProvider).createFragmentFactory(...)` and install the resulting `FragmentFactory` on the **parent** `FragmentManager` before committing the child.
- `Streamer`/`DefaultPublicationParser` constructor takes `pdfFactory: PdfDocumentFactory?`. Pass `PdfiumDocumentFactory(context)`.
- Locator shape: page index is read from `Locator.locations` via `locations.pageIndex` (0-based on Kotlin side).
- `PdfNavigatorFragment` does **not** support restore-after-process-death → handle `RestorationNotSupportedException` via `PdfNavigatorFragment.createDummyFactory(...)`.
- Reference files:
  - https://github.com/readium/kotlin-toolkit/blob/3.1.2/test-app/src/main/java/org/readium/r2/testapp/reader/PdfReaderFragment.kt
  - https://github.com/readium/kotlin-toolkit/blob/3.1.2/readium/navigator/src/main/java/org/readium/r2/navigator/pdf/PdfNavigatorFragment.kt
  - https://github.com/readium/kotlin-toolkit/blob/3.1.2/docs/guides/pdf.md
  - https://github.com/readium/kotlin-toolkit/blob/3.1.2/readium/adapters/pdfium/README.md

### Pre-existing plugin state

- iOS PDF parsing is **already wired**: [`flutter_readium/ios/flutter_readium/Sources/flutter_readium/Readium.swift:48`](flutter_readium/ios/flutter_readium/Sources/flutter_readium/Readium.swift:48) already passes `DefaultPDFDocumentFactory()` to `DefaultPublicationParser`. The gap is only the navigator instantiation site at [`ReadiumReaderView.swift:114`](flutter_readium/ios/flutter_readium/Sources/flutter_readium/ReadiumReaderView.swift:114), which hard-codes `EPUBNavigatorViewController`.
- Android PDF parsing has a marked placeholder: [`ReadiumReader.kt:212`](flutter_readium/android/src/main/kotlin/dk/nota/flutter_readium/ReadiumReader.kt:212) literally has `pdfFactory = null, // PdfiumDocumentFactory(context)` plus the matching commented dependency line at [`flutter_readium/android/build.gradle:99-100`](flutter_readium/android/build.gradle:99) for PSPDFKit.
- `Publication.conformsToReadiumEbook` / `conformsToReadiumAudiobook` already exist at [`publication.dart:205-209`](flutter_readium_platform_interface/lib/src/shared/publication/publication.dart:205); add `conformsToReadiumPDF` alongside.
- `PublicationFormatEnum` at [`format.dart:66`](flutter_readium_platform_interface/lib/src/shared/publication/format.dart:66) currently has just `epub` and `video`.

---

## Phases

### Phase 0 — Native dependencies & parser wiring

**Android — `flutter_readium/android/build.gradle:99-100`**
- Remove the two PSPDFKit comment lines.
- Add: `implementation "org.readium.kotlin-toolkit:readium-adapter-pdfium:$readium_version"`.

**Android — `flutter_readium/android/src/main/kotlin/dk/nota/flutter_readium/ReadiumReader.kt:207-213`**
- Import `org.readium.adapter.pdfium.document.PdfiumDocumentFactory`.
- Replace `pdfFactory = null` with `pdfFactory = PdfiumDocumentFactory(context)`.

**iOS — verify only.** Confirm `ReadiumShared` / `ReadiumStreamer` / `ReadiumNavigator` already cover the PDF symbols on the pinned 3.7.0 podspec; no podspec change expected.

**Acceptance:** opening a `.pdf` URL via `openPublication()` produces a `Publication` (manifest visible) on both platforms, even though presenting it still fails.

### Phase 1 — Dart format detection

**`flutter_readium_platform_interface/lib/src/shared/publication/format.dart`**
- Add `static const pdf = PublicationFormat(PublicationFormatEnum.pdf);` and the matching enum case at `format.dart:66`.
- Extend `fromMIMETypes` (`format.dart:32-50`) to map `application/pdf` and the `.pdf` extension to `PublicationFormat.pdf`.

**`flutter_readium_platform_interface/lib/src/shared/publication/publication.dart`**
- Add `conformsToReadiumPDF` getter parallel to `conformsToReadiumEbook` (around `:205-209`). The Readium PDF profile URL is `https://readium.org/webpub-manifest/profiles/pdf`.

**Acceptance:** `PublicationFormat.fromPath('/x.pdf', mimetype: 'application/pdf')` returns `PublicationFormat.pdf`. No behavior change for EPUB.

### Phase 2 — iOS PDF navigator

Today `ReadiumReaderView.swift` is EPUB-only and entangled with WebView-specific concerns (`initUserScripts`, JS `evaluateJavaScript`, scroll-mode page math). Do **not** bolt PDF onto the same class — split.

**Refactor**
- Rename current class to `EPUBReaderView` (file: `EPUBReaderView.swift`). No logic change.
- Make `ReadiumReaderViewFactory.swift` pick `EPUBReaderView` vs `PDFReaderView` based on `FlutterReadiumPlugin.instance!.getCurrentPublication()!`'s media type / conformance.

**New `PDFReaderView.swift`** modeled on https://github.com/readium/swift-toolkit/blob/3.7.0/TestApp/Sources/Reader/PDF/PDFViewController.swift:
- Conform to `PDFNavigatorDelegate` (which is `VisualNavigatorDelegate, SelectableNavigatorDelegate`).
- Instantiate `PDFNavigatorViewController(publication:, initialLocation:, config:, delegate:, httpServer: sharedReadium.httpServer!)`.
- Wire the same status events (`emitReaderStatusChanged`), `locationDidChange`, `presentError`, `didFailToLoadResourceAt`.
- Drop everything WebView/JS-related — no `initUserScripts`, no `evaluateJavascript`, no `goBackwardInScrollMode`/`goForwardInScrollMode`, no custom CSS injection.
- `applyDecorations`: PDF navigator does **not** conform to `DecorableNavigator` in 3.7.0 — log a warning and no-op. Keep the method-channel surface but make it inert.
- `setPreferences`: route to `submitPreferences(_ preferences: PDFNavigator.Preferences)`. See Phase 5 — initial PR can no-op with a TODO.

**Locator emission**: forward PDF locator as-is (1-based `position` + `fragments: ["page=N"]`).

**Acceptance:** open a PDF in the example app on iOS, tap-to-page-forward/back works, `onTextLocatorChanged` emits a locator whose `locations.position` advances.

### Phase 3 — Android PDF navigator

Mirror the EPUB structure.

**New `navigators/PdfNavigator.kt`** parallel to `navigators/EpubNavigator.kt`:
- Hold a `PdfNavigatorFactory` constructed with `publication` + `PdfiumEngineProvider()`.
- Expose `fragmentFactory`, `initialLocator`, `initialPreferences = PdfiumPreferences()`.
- Forward the same `VisualListener` events `EpubNavigator` currently emits.

**New `fragments/PdfReaderFragment.kt`** parallel to `fragments/EpubReaderFragment.kt`:
- Use `childFragmentManager.fragmentFactory = navigatorFactory.createFragmentFactory(...)` **before** committing the child (instantiation fails otherwise — see upstream test app).
- Implement `Listener` interface the widget will hook into.

**`ReadiumReader.kt`**
- Add `pdfEnabled` state key + `pdfNavigator: PdfNavigator?` field, mirroring `epubEnabled`/`epubNavigator`.
- Add `fun pdfEnable(...)` parallel to `epubEnable(...)` at `ReadiumReader.kt:773`.
- Add state save/restore branch (`pdfNavigatorStateKey`). Catch `RestorationNotSupportedException` and fall back to `PdfNavigatorFragment.createDummyFactory(...)`.

**`ReadiumReaderWidget.kt`**
- Replace hard-coded `EpubReaderFragment` (lines 16, 48, 134, 144) with a runtime dispatch on publication type.
- Implement both `EpubReaderFragment.Listener` and the new `PdfReaderFragment.Listener` (or extract a common reader-fragment listener interface).

**Acceptance:** open a PDF on Android, page navigation works, `currentTextLocator` emits a locator whose `pageIndex` advances.

### Phase 4 — Locator convention (cross-platform alignment)

Pick **one** canonical Dart representation and document it. Proposed:
- `Locator.locations.position` = 1-based page number (matches Swift exactly; Android side adapts by `pageIndex + 1`).
- `Locator.locations.fragments` includes `"page=N"` (Swift produces this for free; Android side adds it).
- `Locator.href` = the single PDF resource href.

Add a 4–6 line section to `CLAUDE.md` under "Conventions" describing the PDF locator shape. Add a comment at the Kotlin emission site explaining the `+1` adjustment.

**Acceptance:** a round-trip `goToLocator(page=5)` → emitted locator → `goToLocator(emitted-locator)` lands on the same page on both platforms.

### Phase 5 — Preferences

PDFium and PDFKit each expose their own `Preferences`/`Settings` classes. The plugin's `FlutterEPUBPreferences` is EPUB-specific (font, theme, columnCount) and does not translate. PDF-relevant prefs include fit-mode, page-spread, scroll-vs-paged.

- Add `FlutterPDFPreferences` on both native sides — start minimal (scroll mode, fit mode), serialise to PDFium / PDFKit preference types respectively.
- Route via the existing `setPreferences` method-channel call; channel handler picks the right preferences class based on which navigator is active.
- Dart side: add a `PDFReaderPreferences` model mirroring `EPUBReaderPreferences`.

If this gets large, ship Phase 0–4 first with a no-op `setPreferences` path on PDF, and do Phase 5 in a follow-up PR.

**Acceptance:** toggling scroll mode in the example app's settings sheet changes layout on a PDF.

### Phase 6 — Selection (no decorations)

- **iOS**: `PDFNavigatorViewController` conforms to `SelectableNavigator` → wire `currentSelection`, `clearSelection`, selection-changed delegate callbacks. `applyDecorations` stays a no-op for PDF.
- **Android**: `PdfNavigatorFragment` selection surface in 3.1.2 is engine-dependent. If selection is engine-side only and not surfaced as `VisualNavigator` events, document the gap and ship without selection on Android.

**Acceptance:** iOS — long-press in a PDF surfaces a selection event to Dart. Android — implemented if exposed, otherwise documented as a platform limitation.

### Phase 7 — TOC & reading-order verification

No code changes expected — `Publication.tableOfContents` already comes through the manifest. Verify:
- TOC entries in a PDF have `href` pointing at the single PDF resource with a `#page=N` fragment.
- Example app's TOC navigation works (tap → `goToLocator` → PDF jumps).

If `currentTocLinkFromLocator` (Swift) and its Kotlin equivalent produce nonsense for PDFs (e.g. always pick the first TOC entry because every entry matches the same `href`), fix to also compare on page fragment.

### Phase 8 — Example app integration

Per CLAUDE.md, the example app is the canonical smoke test target.

- Add a sample PDF to `flutter_readium/example/` assets (a small Project-Gutenberg PDF works) or fetch from a public URL.
- Surface "Open PDF" in the bookshelf UI; use the new `PublicationFormat.pdf` for the format chip.
- Manually exercise on both iOS simulator and an Android emulator: open, page forward 5 pages, jump via TOC, kill and restart (state restoration), close.

### Phase 9 — Docs & changelog

- `CHANGELOG.md` — add a top-level "Unreleased / Added: PDF support (iOS via PDFKit, Android via PDFium)" entry.
- `README.md` (root + plugin) — update the supported-formats line.
- `CLAUDE.md` "Gotchas" — replace "PDF adapter code is present-but-commented" with the current state (PDFium enabled, PSPDFKit available but not wired). Move LCP-only mention into its own bullet.
- `docs/architecture.md` and the relevant `docs/api-reference/*` — update if they describe supported formats.

---

## Suggested PR breakdown

| PR | Phases | Why | Risk |
|---|---|---|---|
| 1 | 0 + 1 | Add deps, flip parser switches, Dart format enum. No behavior change for existing EPUB users; PDF still won't render. | Low — touches build files + one enum + one getter. |
| 2 | 2 + 3 + 4 | Native navigators on both platforms, locator convention. The "PDFs now open" PR. | Medium-high. The big one. |
| 3 | 5 + 6 + 7 | Preferences, selection, TOC verification. | Medium. |
| 4 | 8 + 9 | Example app + docs. | Low. |

PR 1 is shippable on its own. PR 2 is the substantive deliverable.

---

## Risks & gotchas

1. **Android FragmentFactory ordering** — `PdfNavigatorFragment` instantiates a child fragment via `childFragmentManager`. The factory must be installed on the **parent** `FragmentManager` **before** the commit, or `Fragment.instantiate` throws. Mirror the upstream test app's order exactly.
2. **Android state restoration** — `PdfNavigatorFragment` does not support restore-after-process-death; catch `RestorationNotSupportedException` and use `createDummyFactory`. Existing EPUB save/restore path will mislead you if you copy-paste it without this branch.
3. **iOS decorations API mismatch** — `PDFNavigatorViewController` does not conform to `DecorableNavigator`. The Dart `applyDecorations` call must no-op gracefully for PDFs (and ideally surface a `decorationsSupported: false` capability flag to Dart so the example app can hide the highlight UI).
4. **Locator divergence** — kotlin-toolkit speaks `pageIndex` (0-based); swift-toolkit speaks `position` (1-based) + `fragments: ["page=N"]`. Pick one convention at the Dart boundary or every consumer will get bugs. Phase 4 fixes this.
5. **Web is out of scope** — `reader_widget_switch.dart` already routes web to the webview. The web path will throw / behave undefined if asked to open a PDF; that's acceptable for v1 but make the error clear (or hide PDFs in the example when running on web).
6. **Version drift in docs** — CLAUDE.md's policy is to keep upstream version pins in sync across docs. Don't bump readium versions as part of this work.

---

## Progress log

Update this section as phases land. Branches are cut from `feat/pub-dev-readiness` (the integration branch ahead of the next pub.dev release) — do not branch from `main`.

CHANGELOG entries are **deferred until the full PDF feature is complete** — do not add per-phase CHANGELOG bullets. Phase 9 collects everything into a single Unreleased entry.

- ✅ **Phase 0** — native deps & parser wiring (Android `readium-adapter-pdfium` + `PdfiumDocumentFactory`; iOS already wired)
- ✅ **Phase 1** — Dart format detection (`PublicationFormat.pdf`, `Publication.conformsToReadiumPDF`)
- ✅ **Phase 2** — iOS PDF navigator. `ReadiumReaderView` (class) split into a `ReadiumReaderView` (protocol) + concrete `EPUBReaderView` + new `PDFReaderView`. `ReadiumReaderViewFactory` dispatches on `Publication.Profile.pdf` / first reading-order `MediaType.pdf`. PDF view no-ops `applyDecorations` (no `DecorableNavigator`) and `syncToLocator` (no media-overlay sync); `setPreferences` is stubbed pending Phase 5.
- ✅ **Phase 3** — Android PDF navigator. New `navigators/PdfNavigator.kt` wraps `PdfNavigatorFactory(publication, PdfiumEngineProvider())`. New `fragments/PdfReaderFragment.kt` installs the navigator's `FragmentFactory` on `childFragmentManager` before `super.onCreate`, then commits `PdfNavigatorFragment` via `replace(class, args, tag)`. New `models/PdfReaderViewModel.kt`. `ReadiumReader` gains `pdfEnable`/`attachPdfNavigator`/`pdfClose`/`pdfGoTo*` parallel to EPUB. `ReadiumReaderWidget` reads `Publication.Profile.PDF` / `MediaType.PDF` at init and dispatches all method-channel calls accordingly. State save records `pdfEnabledKey` but does **not** restore the navigator (upstream `PdfNavigatorFragment` does not support process-death restoration). PDF `setPreferences` / `applyDecorations` are graceful no-ops returning success.
- ✅ **Phase 4** — locator convention. `Locator.locations.position` is canonical for PDF page numbers across iOS + Android (both upstream toolkits emit 1-based `position`; no per-platform translation needed). Documented in CLAUDE.md under Conventions. Updated the "Gotchas" section in CLAUDE.md to reflect that PDF support is now wired (PDFium on Android, PDFKit on iOS) — the old "present-but-commented" note is no longer accurate.
- ✅ **Phase 5** — preferences. New `PDFPreferences` Dart model (`scroll: bool?`, `readingProgression: PDFReadingProgression?`). Exported from `reader` index and exposed on `FlutterReadium`, `FlutterReadiumPlatform`, `ReadiumReaderWidgetInterface`, and `ReadiumReaderChannel` (same `setPreferences` method-channel call). iOS: new `FlutterPDFPreferences.swift` maps to `PDFNavigatorViewController.Preferences` and is applied via `pdfViewController.submitPreferences(_:)`. Android: new `FlutterPdfPreferences.kt` maps to `PdfiumPreferences`; `PdfReaderFragment.updatePreferences()` calls `nav.submitPreferences()`; `PdfNavigator.updatePreferences()` and `ReadiumReader.pdfUpdatePreferences()` chain the call. Fixed pre-existing `pubspec.yaml` bug (stray `  dependencies:` entry) and added `dependency_overrides` to example `pubspec.yaml` so `flutter pub get` resolves the local platform interface.
- ✅ **Phase 6** — selection. `PDFNavigatorViewController` conforms to `SelectableNavigator` — `currentSelection` is accessible on demand (same pattern as EPUB). No full selection→Dart event pipeline exists for either EPUB or PDF (out of scope for v1). Android: `PdfiumNavigatorFragment` does not expose `SelectableNavigator` in kotlin-toolkit 3.1.2 — documented limitation.
- ✅ **Phase 7** — TOC verification & enrichment. iOS: `PDFReaderView.emitOnPageChanged` now enriches the outgoing locator with `tocHref` and `title` by matching `#page=N` fragments in the publication's flattened TOC against `locator.locations.position`. Android: new `ReadiumReader.pdfEnrichLocatorWithTocHref()` does the same; wired in `ReadiumReaderWidget.emitOnPageChanged` for the PDF path. EPUB path unchanged. `currentTocLinkFromLocator` (iOS) and `epubEnrichLocatorWithTocHref` (Android) correctly return nil/original-locator for PDF (no `cssSelector`; EPUB profile guard) — no nonsense output.
- ✅ **Phase 8** — example app integration. Added `pdf_test.pdf` (minimal single-page PDF) to `flutter_readium/example/assets/pubs/`. Updated `PublicationUtils.moveAssetPublicationsToReadiumStorage` to include `.pdf` in the allowed extensions. Updated `_bookFormatFromConformsTo` in `BookshelfPage` to display "PDF" for PDF publications. The `ReadiumReaderWidget` / player page already route PDFs to the visual reader widget correctly. Note: EPUB text settings panel is still shown in the player UI for PDFs (calls are gracefully ignored on the native side).
- _(unstarted)_ Phase 9 — docs & changelog (consolidated CHANGELOG entry lands here)
