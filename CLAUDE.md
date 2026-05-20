# flutter_readium

A Flutter plugin wrapping the [Readium](https://readium.org) toolkits for EPUB / audiobook / WebPub reading. The Dart API is shared across iOS, macOS, Android, and Web; each platform delegates to the matching native Readium toolkit.

## Repo layout

This is a **federated Flutter plugin** with two pub packages and a multi-package root:

- `flutter_readium_platform_interface/` — shared Dart API, models, method-channel contract.
- `flutter_readium/` — app-facing package with native wrappers (iOS/Swift, Android/Kotlin, macOS) and a web implementation (TypeScript → JS bundle in a webview).
  - `example/` — **the smoke-test target.** All UI / behavior changes should be verified by running the example app before declaring a task done.
- `bin/` (repo root) — multi-package developer scripts (see below).

## Upstream Readium toolkits

The native sides are thin wrappers around upstream Readium code — when debugging native behavior, the source of truth is upstream:

- swift-toolkit: https://github.com/readium/swift-toolkit/ — pinned to **3.9.0** in `flutter_readium/ios/flutter_readium.podspec` and the example `Podfile`.
- kotlin-toolkit: https://github.com/readium/kotlin-toolkit/ — pinned to **3.1.2** via `ext.readium_version` in `flutter_readium/android/build.gradle`.
- ts-toolkit (Web): consumed via npm — `@readium/shared`, `@readium/navigator`, `@readium/navigator-html-injectables` (see `flutter_readium/package.json`).

When you need to inspect upstream implementation details (e.g. how a navigator handles a locator, what fields a model uses), read the source on GitHub — do NOT decompile local JARs, .framework bundles, or other build artifacts. Use `gh api` or `WebFetch` against the repos above.

Voice data for TTS comes from https://github.com/readium/speech (refreshed by `bin/update_readium_voice_data`).

When upgrading any toolkit version, check that all three platforms move together where API surface overlaps — divergence between platforms is a recurring source of bugs. Also update every version reference in the docs and README to match the new pinned version, to avoid drift.

## Developer workflow

Key scripts (run from repo root):

- `bin/install` — full bootstrap (pub get, pod install, build JS). Run after clone or dependency changes.
- `bin/forAll <cmd>` — run a command in both pub packages.
- `bin/update_web_example` — rebuild web TS bundle and copy into example. **Run after any TS change.**
- `bin/update_readium_voice_data` — refresh TTS voice data from upstream (requires `jq`).
- `flutter_readium/bin/build_helper_scripts.sh` — rebuild the helper-scripts TS bundle injected into the webview.

Running the example app: `cd flutter_readium/example && flutter run`.

## Conventions

- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/) with scopes (see `git log`). PR titles follow the same format.
- **Branching**: GitHub flow — short-lived feature branches off `main`. `main` is the only relevant branch; any older branches in the repo are historical and should be ignored.
- **Smoke test**: the example app at `flutter_readium/example/` is the canonical end-to-end smoke test. If a change can't be exercised in the example, say so explicitly rather than claiming it's verified.
- **Models & method-channel contract**: keep the Dart side in `flutter_readium_platform_interface` in sync with both native implementations. If you add a method-channel call, all three native sides (Swift, Kotlin, web) need a matching handler — or an explicit `UnimplementedError` if intentionally unsupported.
- **Models**: serialise with hand-written `toJson` / `fromJson` methods. The project no longer uses `json_serializable` or `freezed` code generation — don't reintroduce build_runner-based codegen.
- **Changelog**: when completing a feature or bugfix, make sure to update the CHANGELOG.md file. Anything new goes under Unreleased, until a release.
- **Web JS**: don't hand-edit the built JS in `example/web/`. Edit TS sources, then `bin/update_web_example`.
- **PDF locator shape**: PDFs are represented as a single-resource publication. The canonical position lives in `Locator.locations.position` as a **1-based page number** — this matches the upstream `PDFPositionsService` (swift-toolkit) and `Locator.locations.position` from `PdfNavigatorFragment.currentLocator` (kotlin-toolkit). The PDF resource href is always the single reading-order entry, and the locator's `fragments` carry `"page=N"` on iOS (where the upstream parser produces it). Do not invent a parallel `pageIndex` convention; consumers should read `locations.position` for page navigation and round-trip via `goToLocator`.

### Android

- **Log messages**: every `Log.*` call in Kotlin must start with `::functionName` (double colon, then the exact name of the enclosing function). For lambdas, use the name of the enclosing named function. Example: `Log.d(TAG, "::goBackward. Navigator not ready.")`. Single-colon or missing prefixes are bugs.
- **Navigator null guard**: every `suspend` function that needs the navigator must capture it as a local variable with a `?: run { }` early-return guard, then wrap direct navigator calls in `return withContext(coroutineContext) { }`. Functions that only call other wrapper functions (e.g. `evaluateJavascript`) do not need their own guard — delegate instead. Example:
  ```kotlin
  val navigator = epubNavigator ?: run {
      PluginLog.w(TAG, "::myFunction. Navigator not ready.")
      return
  }
  return withContext(coroutineContext) { navigator.someCall() }
  ```

## Gotchas

- The example app's `Podfile.lock` and `pubspec.lock` are committed — be intentional about lockfile changes in diffs.
- The plugin exposes a singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`); don't reintroduce per-instance state without considering the existing global publication lifecycle.
- The plugin targets EPUB / WebPub (with or without pre-recorded audio) and PDF on iOS + Android. PDF support uses PDFKit on iOS and PDFium via `readium-adapter-pdfium` on Android — the PSPDFKit adapter remains commented out in `android/build.gradle` for the commercial-license path. LCP support is still gated behind a `#if LCP` flag on iOS and a commented `readium-lcp` dependency on Android — don't enable it without a deliberate plan.

## Testability (marionette)

- **Launching the app:** Run `flutter run` with `run_in_background: true` (the command never terminates while the app is running). Poll the background task output for `A Dart VM Service ... is available at: <uri>`, extract the URI, then `marionette register <name> <uri>/ws`. Do not use a foreground Bash call — it will always hit the timeout. Poll pattern: `for i in $(seq 1 30); do grep -m1 "Dart VM Service" <output_file> 2>/dev/null && break; sleep 1; done`
- When adding interactive UI elements to the example app that should be exercisable via marionette, add a `ValueKey<String>` to the widget (especially `TextField`s inside `Autocomplete`). This makes `marionette tap --key` and `marionette enter-text --key` reliable.
- Prefer `tap --key` or `tap --text` over coordinate-based taps (`tap --x --y`). Coordinate taps are fragile — elements can overlap or shift between devices, leading to flaky tests that hit the wrong target.
- PDF content does not render visibly in marionette screenshots — marionette captures the Flutter compositing layer, which cannot reach native platform views (PDFKit/PDFium). When you need to visually verify native view content, use `xcrun simctl io booted screenshot /tmp/screen.png` instead (captures the full simulator framebuffer). For routine PDF navigation verification, check `marionette get-logs` for `onPageChanged` locator position.
