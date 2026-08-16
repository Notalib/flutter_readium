# Custom Font Declarations

## Goal

Make the example's font choices honest and cross-platform:

- `OpenDyslexic` uses the font bundled by the Readium toolkits.
- A separate freely licensed font exercises app-provided font assets.
- iOS, Android, and web receive equivalent font-family declarations.

## Current Findings

- The example already lists `OpenDyslexic`, and Dart submits that exact family name.
- Swift Toolkit 3.11.0 and Kotlin Toolkit 3.2.0 both bundle OpenDyslexic.
- The example's OpenDyslexic files are registered only with Flutter. Readium's native WebViews never use those Flutter font registrations, so they do not test custom reader fonts.
- Kotlin Toolkit 3.2.0 copies the plugin's navigator configuration, adds `readium/.*` to served assets, and declares `readium/fonts/OpenDyslexic-Regular.otf`.
- Android runtime evidence confirms the preference and declaration are applied, but WebView blocks `https://readium_assets/readium/fonts/OpenDyslexic-Regular.otf` from the `https://readium_package` origin because the asset response has no `Access-Control-Allow-Origin` header.
- Kotlin Toolkit fixed this upstream in [PR #797](https://github.com/readium/kotlin-toolkit/pull/797) / commit `f038367`. Release 3.3.0 adds `Access-Control-Allow-Origin: *` to served asset responses and explicitly lists EPUB fonts as the affected use case.

## Implementation

1. Add immutable Dart models for a reader font family and its faces.
   - Family name.
   - Optional fallback family names.
   - Flutter asset path per face.
   - Optional normal/italic style and numeric weight or weight range.
   - Hand-written map serialization; no code generation.

2. Upgrade the Android Readium dependencies from 3.2.0 to 3.3.0.
   - Treat this as the fix for built-in OpenDyslexic; do not duplicate the upstream CORS response handling in the plugin.
   - Review Kotlin Toolkit's 3.3.0 migration notes and compile all Android source before continuing.

3. Add `fontFamilyDeclarations` to `ReadiumReaderWidget` on native and web.
   - Default to an empty list.
   - Pass serialized declarations in native platform-view creation parameters.
   - Pass declarations to the web navigator constructors.

4. Resolve Flutter assets in each implementation.
   - iOS: use `FlutterPluginRegistrar.lookupKey(forAsset:)`, resolve the main-bundle file, and build `CSSFontFamilyDeclaration` values.
   - Android: use Flutter asset lookup keys, authorize only the declared asset paths in `servedAssets`, and build Kotlin Toolkit font-family declarations.
   - Web: load each declared Flutter asset, create Blob-backed `@font-face` CSS, and inject it into EPUB and WebPub resources through navigator injectable rules.
   - Invalid declarations should fail clearly during reader creation rather than silently falling back.

5. Update the example.
   - Keep `OpenDyslexic` as a toolkit-provided dropdown entry.
   - Replace the example OpenDyslexic files with one free font family that is visually distinct and permits redistribution. Prefer Atkinson Hyperlegible unless its current license or file source cannot be verified.
   - Declare the custom family on `ReadiumReaderWidget` and add it to the dropdown.
   - Preserve license attribution beside the font assets.

6. Add focused coverage.
   - Dart model serialization and widget creation-parameter tests.
   - Kotlin conversion/configuration tests for asset serving, style, and weight.
   - Swift model/configuration tests where the package test seam permits it.
   - TypeScript tests for generated `@font-face` CSS and injection rules.
   - Example integration smoke test selecting both built-in OpenDyslexic and the custom family.

## Android Regression Check

After upgrading to Kotlin Toolkit 3.3.0, open a reflowable EPUB and WebPub and select `OpenDyslexic`.

- Body text must visibly use OpenDyslexic.
- Logcat must not contain the previous CORS rejection for `OpenDyslexic-Regular.otf`.
- Generic `sans-serif`, `serif`, and `monospace` preferences must remain functional.

## Validation

- `bin/format`
- `bin/analyze`
- Relevant Dart unit/widget tests
- Web typecheck and unit tests
- `./gradlew :flutter_readium:compileDebugKotlin` from `flutter_readium/example/android`
- `flutter build ios --no-codesign` from `flutter_readium/example`
- Marionette smoke test on Android and iOS for both dropdown entries

## Non-goals

- Downloadable/network fonts.
- Runtime mutation of font declarations after creating the reader.
- Automatically exposing every font installed on the operating system.
