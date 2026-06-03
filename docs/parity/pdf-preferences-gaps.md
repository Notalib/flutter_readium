# PDF Preferences Gaps (iOS)

> **✅ Implemented**. `offsetFirstPage`, `spread` (`PDFSpread`), and `visibleScrollbar` are now surfaced in `reader_pdf_preferences.dart`. Retained for reference.

**Type:** Upstream feature
**Platforms affected:** iOS
**Estimated effort:** S

## Context

The iOS `PDFNavigatorViewController.Preferences` struct in swift-toolkit 3.9.0 exposes nine configurable properties. The current `PDFPreferences` Dart model covers four of them (via the unified `layout`, `readingProgression`, `pageSpacing`, and `fit` fields). Three additional properties from the upstream iOS struct are not yet surfaced to Dart:

- **`offsetFirstPage`** (`Bool?`) — When `true`, the first page is displayed alone (not paired with a second page in two-up mode). Useful for the common case where the cover occupies the first page and the remaining pages begin on the right.
- **`spread`** (`Spread?` / `Bool?`) — Whether the publication should be rendered with a synthetic spread (dual-page view). This is distinct from `layout` and controls pairing, not scroll axis.
- **`visibleScrollbar`** (`Bool?`) — Whether the scroll indicator is shown while scrolling.

Of these, `offsetFirstPage` and `spread` are the most consumer-relevant: they directly affect how comic books and illustrated books look in two-page viewing mode.

Note: The Android `PdfiumPreferences` (kotlin-toolkit 3.2.0) does not expose `offsetFirstPage` or `visibleScrollbar`, so these two preferences would be iOS-only. `spread` may be available on Android; verify against the `PdfiumPreferences` source during implementation.

## Current state

- **Dart model** (`flutter_readium_platform_interface/lib/src/reader/reader_pdf_preferences.dart`): Four fields — `layout`, `readingProgression`, `pageSpacing`, `fit`.
- **iOS native** (`FlutterPDFPreferences.swift`): Reads `layout`, `readingProgression`, `fit`, `pageSpacing` from the JSON map. No handling for `offsetFirstPage`, `spread`, or `visibleScrollbar`.
- **Android** (`FlutterPdfPreferences.kt`): Maps its own set of fields; Android `PdfiumPreferences` does not include `offsetFirstPage` or `visibleScrollbar`.

## Proposed approach

1. **Dart model** (`reader_pdf_preferences.dart`): Add three new nullable fields — `offsetFirstPage: bool?`, `spread: bool?`, `visibleScrollbar: bool?` — with matching `toJson` / `fromJson` entries. Include doc comments noting Android support status for each.
2. **iOS** (`FlutterPDFPreferences.swift`): Read `offsetFirstPage`, `spread`, and `visibleScrollbar` from the JSON map and set them on the `PDFNavigatorViewController.Preferences` struct.
3. **Android**: If `PdfiumPreferences` in kotlin-toolkit 3.2.0 exposes `spread`, map it from the Dart preference. Otherwise, document `spread: bool?` as iOS-only in the Dart model and in `docs/api-reference/preferences.md`.
4. **Docs** (`docs/api-reference/preferences.md`): Update the PDF preferences table to include the three new fields with their platform support annotations.

## Scope boundaries

- `visibleScrollbar` is a cosmetic preference. If it proves complicated to wire (e.g. requires extra Readium configuration), defer it to a separate follow-up.
- This plan does not cover PDF annotation or search — those are separate upstream features not yet exposed.

## Risks / open questions

1. **Android `spread` availability**: The kotlin-toolkit `PdfiumPreferences` source was not accessible at audit time. During implementation, verify whether `spread` exists in kotlin-toolkit 3.2.0. If it does, add Android support in the same change to avoid divergence. If not, mark it iOS-only.
2. **`spread` vs `layout` interaction**: On iOS, `spread` interacts with `scroll` (i.e. `layout`). Document the expected behaviour in code comments to prevent consumer confusion. For example, spread only takes effect in non-scrolling layouts.

## Verification

1. Run `bin/analyze` and `bin/format` from the repo root.
2. In the example app on iOS, open a multi-page PDF and apply:
   - `PDFPreferences(offsetFirstPage: true, spread: true)` — confirm the first page is displayed alone and subsequent pages pair up.
   - `PDFPreferences(visibleScrollbar: false)` — confirm the scrollbar is hidden while swiping.
3. Confirm that omitting the new fields (passing `null`) leaves existing behaviour unchanged on both iOS and Android.
4. On Android, confirm the preferences serialize and deserialize without error even if the new fields are unsupported (graceful no-op).
