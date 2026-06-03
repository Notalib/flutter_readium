# EPUB Theme Preference (Undocumented Gap)

**Type:** Upstream feature
**Platforms affected:** iOS, Android
**Estimated effort:** S

## Context

The `docs/api-reference/preferences.md` file references an `EpubThemeType` enum with values `light`, `dark`, and `sepia` and says it "overrides `backgroundColor` and `textColor` when set". However, this field does not exist in the `EPUBPreferences` Dart model (`reader_epub_preferences.dart`), nor is there any handling for it in the iOS or Android native implementations. There is no `EpubThemeType` enum anywhere in the codebase.

The upstream swift-toolkit `EPUBPreferences` also has no built-in `theme` property — themes are typically implemented by setting specific `backgroundColor` + `textColor` pairs. The docs appear to describe an intended design that was never implemented.

Exposing a named theme enum would be valuable for consumers building settings UIs: they can offer "Light / Dark / Sepia" toggle buttons without having to know the exact colour values for each theme and apply them consistently across publication types.

## Current state

- **Docs** (`docs/api-reference/preferences.md` line 41): References `theme: EpubThemeType?` as a preference field.
- **Dart model** (`reader_epub_preferences.dart`): No `theme` field and no `EpubThemeType` enum — anywhere in the codebase.
- **iOS / Android**: No theme-related handling in any native file.
- **Web** (`epubPreferences.ts`): No `theme` key in the `IEpubPreferences` mapping.

This is a doc/code mismatch: the documentation describes a feature that does not exist in the implementation.

## Proposed approach

Two options, requiring a product decision:

**Option A — Implement the feature**:
1. Add `EpubThemeType` enum (light, dark, sepia) to the platform interface.
2. Add `theme: EpubThemeType?` to `EPUBPreferences` with serialisation.
3. On iOS and Android, translate the enum to predefined `backgroundColor` + `textColor` pairs before submitting to the upstream navigator (since neither toolkit has a native `theme` concept). Keep the colour constants in the native layer so they can be tuned without a Dart API change.
4. On web, translate to the equivalent `backgroundColor` / `textColor` CSS values.
5. Specify that `theme` takes precedence over `backgroundColor` / `textColor` when both are set, and document this in the API.

**Option B — Remove the undocumented reference**:
1. Delete the `theme` row from `docs/api-reference/preferences.md`.
2. Add a note that theme-style presets can be built on top of `backgroundColor` and `textColor`, and provide example presets in the docs.

Option A adds genuine consumer value (no need to know colour values). Option B is correct immediately and defers the feature to when it can be implemented properly.

**Recommendation**: Decide before implementation. If Option A is chosen, proceed as described. Either way, the doc/code mismatch must be resolved in the same change.

## Scope boundaries

- This plan does not add a "custom theme" concept beyond the three named values.
- Accessibility contrast levels (e.g. high-contrast variants of each theme) are out of scope.

## Risks / open questions

1. **Colour values**: What exact `backgroundColor` and `textColor` values define "dark" and "sepia"? These need to be agreed upon before implementation to avoid inconsistency between iOS, Android, and web.
2. **Interaction with `publisherStyles`**: When `publisherStyles` is `true`, `textColor` and `backgroundColor` are ignored by the upstream navigator. Does setting a `theme` implicitly set `publisherStyles: false`? This interaction must be documented.
3. **Option B risk**: Simply deleting the docs row may confuse consumers who have already read the docs. A short changelog entry ("theme preference moved to a follow-up") would soften the impact.

## Verification

(If Option A is chosen):
1. Run `bin/analyze` and `bin/format` from the repo root.
2. Apply `EPUBPreferences(theme: EpubThemeType.dark, publisherStyles: false)` on iOS, Android, and web in the example app.
3. Confirm the reader background is dark and text is light on all three platforms with consistent colour values.
4. Apply `theme: EpubThemeType.light` and confirm the reader returns to a white background.
5. Confirm that explicitly setting `backgroundColor` alongside `theme` is documented to describe which wins.
