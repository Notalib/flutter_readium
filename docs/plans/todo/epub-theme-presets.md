# EPUB Theme Presets (QoL Improvement)

**Type:** Plugin QoL improvement
**Platforms affected:** iOS, Android, Web
**Estimated effort:** S-M

## Goal

Provide a small, plugin-owned EPUB theme presets helper so consumers can opt into named reading
themes such as `light`, `dark`, and `sepia` without hand-authoring the same color pairs in every
app.

## Chosen direction

Implement this as a **Dart-only convenience layer**. Do not add any method-channel, native, or web
bridge fields. The preset helper should resolve to ordinary `EPUBPreferences` before any platform
handoff.

This keeps the feature low-risk, avoids pretending there is upstream toolkit parity to maintain,
and preserves full consumer control through the existing low-level preferences model.

## Current state

- `EPUBPreferences` already exposes the low-level knobs needed to express themes:
   `backgroundColor`, `textColor`, `publisherStyles`, and related typography/layout fields.
- No built-in preset enum or helper exists in the public Dart API.
- The docs are accurate again: there is no stale `EpubThemeType` contract to maintain.

## API shape

Preferred first pass:

1. Add `enum EpubThemePreset { light, dark, sepia }`.
2. Add a convenience conversion in Dart, using one of these shapes:
    - `EPUBPreferences.fromPreset(EpubThemePreset preset)`
    - `EpubThemePreset.toPreferences()`
3. Document the override pattern explicitly, for example:
    `EpubThemePreset.sepia.toPreferences().copyWith(fontSize: 1.1)`.

Recommendation: prefer `EpubThemePreset.toPreferences()` so the enum owns the preset mapping and
`EPUBPreferences` stays focused on raw preference data.

## Concrete preset contract

First pass should ship exactly three presets:

- `light`
- `dark`
- `sepia`

Each preset should:

- set `backgroundColor`
- set `textColor`
- set `publisherStyles: false`

Do **not** include extra typography/layout opinions in v1. Keep the helper narrowly about color
and reading-surface defaults so it remains predictable.

## Suggested color policy

Choose stable plugin-owned color constants and keep them in Dart:

- `light`: neutral white/near-black
- `dark`: near-black background with warm off-white text
- `sepia`: low-contrast warm paper tone with dark brown text

Exact values should be chosen once and reused in docs/examples. Avoid platform-specific variants in
v1 unless a visual inconsistency is proven.

## Files to change

- `flutter_readium_platform_interface/lib/src/reader/reader_epub_preferences.dart`
   - add `EpubThemePreset`
   - add preset-to-preferences helper
- `flutter_readium_platform_interface/test/`
   - add or extend model tests for preset conversion
- `docs/guides/preferences.md`
   - document the presets helper and override pattern
- `docs/api-reference/preferences.md`
   - mention the helper as a convenience layer, not a transport field
- `flutter_readium/example/lib/`
   - optionally add a small preset picker or example usage snippet if there is already a suitable
      settings surface
- `flutter_readium_platform_interface/CHANGELOG.md`
   - add a consumer-facing entry if public API is added there

## Task breakdown

### Task 1 — add the Dart API

- Add `EpubThemePreset` alongside the EPUB preferences model.
- Add a Dart-only helper for converting a preset into `EPUBPreferences`.
- Keep the helper pure and side-effect free.

### Task 2 — test the mapping

- Add model tests asserting each preset maps to the expected colors.
- Add a test proving consumers can still override fields with `copyWith()` after starting from a
   preset.

### Task 3 — document usage

- Document the helper in the preferences guide.
- Show the recommended override pattern.
- Make it explicit that this is a plugin convenience feature, not an upstream Readium preference.

### Task 4 — optional example app wiring

- If the existing settings UI has a natural place, add a basic preset picker.
- If not, keep this task out of scope and only document usage.

## Non-goals

- No new native or web bridge fields
- No `theme` field serialized over the method channel
- No platform-specific theme engine
- No high-contrast or custom user-defined preset system in the first pass

## Open questions

1. Should the example app expose the presets immediately, or should v1 be API-and-docs only?
2. Do we want to expose the preset colors as public constants, or keep them private to the helper?
3. Is `publisherStyles: false` always the right preset default, or should the helper leave it
    unset and mention the tradeoff in docs?

## Verification

1. Run `bin/analyze` and `bin/format` from the repo root.
2. Run the relevant Dart tests for the platform-interface package.
3. In the example app, apply each preset to the same EPUB on iOS, Android, and web.
4. Confirm the visual result is acceptably consistent across platforms.
5. Confirm consumers can still override individual fields after starting from a preset.
