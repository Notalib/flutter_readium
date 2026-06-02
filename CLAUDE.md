# flutter_readium

A Flutter plugin wrapping the [Readium](https://readium.org) toolkits for EPUB / audiobook / WebPub reading. The Dart API is shared across iOS, Android, and Web; each platform delegates to the matching native Readium toolkit. The Flutter macOS desktop target registers a no-op stub only — native macOS is unsupported by upstream swift-toolkit.

## Repo layout

This is a **federated Flutter plugin** with two pub packages and a multi-package root:

- `flutter_readium_platform_interface/` — shared Dart API, models, method-channel contract.
- `flutter_readium/` — app-facing package with native wrappers (iOS/Swift, Android/Kotlin, macOS stub) and a web implementation (TypeScript → JS bundle in a webview).
  - `example/` — **the smoke-test target.** All UI / behavior changes should be verified by running the example app and using marionette to confirm implementation before declaring a task done.
- `bin/` (repo root) — multi-package developer scripts (see below).

## Upstream Readium toolkits

The native sides are thin wrappers around upstream Readium code — when debugging native behavior, the source of truth is upstream:

- swift-toolkit: https://github.com/readium/swift-toolkit/ — pinned in `flutter_readium/ios/flutter_readium.podspec` and the example `Podfile`.
- kotlin-toolkit: https://github.com/readium/kotlin-toolkit/ — pinned via `ext.readium_version` in `flutter_readium/android/build.gradle`.
- ts-toolkit (Web): consumed via npm — `@readium/shared`, `@readium/navigator`, `@readium/navigator-html-injectables` (see `flutter_readium/package.json`).

When you need to inspect upstream implementation details (e.g. how a navigator handles a locator, what fields a model uses), read the source on GitHub — do NOT decompile local JARs, .framework bundles, or other build artifacts. Use `gh api` or `WebFetch` against the repos above.

If unsure about plugin architecture, be sure to read the README.md files, /docs/architecture.md and /docs/api-reference files.

Voice data for TTS comes from https://github.com/readium/speech (refreshed by `bin/update_readium_voice_data`).

When upgrading any toolkit version, check that all three platforms move together where API surface overlaps — divergence between platforms is a recurring source of bugs. Keep the build/package files above as the source-of-truth, and avoid duplicating exact version numbers broadly in docs.

## Developer workflow

Scripts in `bin/` source `bin/_common.sh`, so they're location-independent (run from any directory) and self-bootstrap the toolchain on PATH for non-interactive shells (CI / AI agents). Run them directly (`bash bin/<script>`), never via `bash -lc`. Use `bin/doctor` to check the toolchain resolves.

Key scripts:

- `bin/doctor` — verify `dart`/`flutter`/`node`/`npm` resolve; exits non-zero if a required tool is missing.
- `bin/install` — bootstrap everything: `pub get` in both packages, `pod update && pod install` for the example, build helper scripts, build web JS, copy JS into example. Run after a fresh clone or when dependencies change.
- `bin/format` — check Dart formatting across all three packages (platform interface, plugin, example). Fails if any file needs reformatting.
- `bin/analyze` — run `dart analyze --fatal-infos --fatal-warnings` across all three packages.
- `bin/typecheck` — type-check the web TypeScript (sources + Jest tests) via `tsc --noEmit` against `web/_scripts/tsconfig.json`. Run after editing any TS in `flutter_readium/web/`. Exits non-zero on a type error.
- `bin/build_js` — build the web bundle (currently `build_dev`; production build is commented out).
- `bin/update_web_example` — `build_js` + copy the bundle into `flutter_readium/example/web/`. Run after editing TS in `flutter_readium/web/`.
- `bin/update_readium_voice_data` — refresh `flutter_readium/assets/voice_data/voices.json` from the upstream `readium/speech` repo (requires `jq`).
- `flutter_readium/bin/build_helper_scripts.sh` — rebuild the helper-scripts TS bundle injected into the webview. Relevant when having touched files in `flutter_readium/assets/_helper_scripts/src`.

## Conventions

- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/) with scopes (see `git log`). PR titles follow the same format.
- **Branching**: GitHub flow — short-lived feature branches off `main`. `main` is the only relevant branch; any older branches in the repo are historical and should be ignored.
- **Smoke test**: the example app at `flutter_readium/example/` is the canonical end-to-end smoke test. **Don't claim verification you haven't done:** if a change can't be exercised in the example app, say so explicitly. This applies to native-only changes, platform-specific edge cases, or anything behind a flag.
- **Models & method-channel contract**: keep the Dart side in `flutter_readium_platform_interface` in sync with both native implementations. **Make intentional gaps explicit:** if you add a method-channel call, all three native sides (Swift, Kotlin, web) need a matching handler — or an explicit `UnimplementedError` if intentionally unsupported. Undocumented silence looks like a bug; an explicit error makes the intent clear.
- **Models**: serialise with hand-written `toJson` / `fromJson` methods. The project no longer uses `json_serializable` or `freezed` code generation — don't reintroduce build_runner-based codegen.
- **Method channel serialization**: Use **JSON strings** (via `json.encode`) for any Readium-owned objects crossing the bridge (`Locator`, `Decoration`, etc.) — the upstream toolkits already own the schema and provide the deserializers, so encoding as a string avoids lossy `[String: Any]` / `Map<String, dynamic>` round-trips. Use **Maps/Dictionaries** only for flat plugin-owned structures (e.g. preferences, action configs) where the shape is simple and fully controlled by this plugin.
- **Web TS: Locator → JSON always via `.serialize()`**: `@readium/shared` Locators store extra location fields (e.g. `cssSelector`, `tocHref`) in `locations.otherLocations` as a `Map<string, any>`. `JSON.stringify(locator)` silently drops all Map entries. Always use `JSON.stringify(locator.serialize())` when emitting a Locator to Dart, and `locator.serialize()` when embedding a locator inside a larger object before stringifying. The same applies to `JSON.parse(JSON.stringify(locator))` deep-clones — use `JSON.parse(JSON.stringify(locator.serialize()))` instead. Reading `otherLocations` entries also requires the Map API: `locator.locations?.otherLocations?.get('cssSelector')`, not `(locator.locations as any)?.cssSelector`.
- **Pre-PR validation**: before considering a task done or creating a PR, run `bin/format` and `bin/analyze` from the repo root. Fix any issues they report. These scripts check all packages (platform interface, plugin, and example app).
- **Changelog**: when completing a feature or bugfix, make sure to update the CHANGELOG.md file. Anything new goes under Unreleased.
- **Web JS**: don't hand-edit the built JS in `example/web/`. Edit TS sources, then `bin/update_web_example`.
- **PDF locator shape**: PDFs are represented as a single-resource publication. The canonical position lives in `Locator.locations.position` as a **1-based page number** — this matches the upstream `PDFPositionsService` (swift-toolkit) and `Locator.locations.position` from `PdfNavigatorFragment.currentLocator` (kotlin-toolkit). The PDF resource href is always the single reading-order entry, and the locator's `fragments` carry `"page=N"` on iOS (where the upstream parser produces it). **Don't duplicate upstream models:** if upstream Readium already models something (locator position, decoration style, etc.), use that representation rather than inventing a plugin-side parallel — alternatives create two sources of truth that diverge over time. Consumers should read `locations.position` for page navigation and round-trip via `goToLocator`.

### Android

- **Kotlin formatting**: after writing or editing any Kotlin file, run `ktlint --format` on it. The `standard:package-name` violation (underscores in `dk.nota.flutter_readium`) is pre-existing and cannot be auto-corrected — ignore it. All other violations must be resolved before committing.
- **Android log messages**: every `PluginLog.*` call in Kotlin must start with `::functionName` (double colon, then the exact name of the enclosing function). For lambdas, use the name of the enclosing named function. Example: `Log.d(TAG, "::goBackward. Navigator not ready.")`. Single-colon or missing prefixes are bugs; wrong function names from copy-paste are also bugs.
- **Android navigator null guard**: every `suspend` function that needs the navigator must capture it as a local variable with a `?: run { }` early-return guard, then wrap direct navigator calls in `return withContext(coroutineContext) { }`. Functions that only call other wrapper functions (e.g. `evaluateJavascript`) do not need their own guard or `withContext` — delegate instead. Example:
  ```kotlin
  val navigator = epubNavigator ?: run {
      PluginLog.w(TAG, "::myFunction. Navigator not ready.")
      return
  }
  return withContext(coroutineContext) { navigator.someCall() }
  ```

## Build / toolchain facts

- Dart SDK: `>=3.8.0 <4.0.0`, Flutter `>=3.32.0`.
- Android: `minSdkVersion 24`, `compileSdk 36`, Kotlin 2.3.21, AGP 8.13.2, Java 18 source/target.
- iOS: requires `use_frameworks!` and `use_modular_headers!` in consuming `Podfile` (see top-level `README.md`).
- Web: webpack 5, TypeScript 5.7+.

## Gotchas

- The example app's `Podfile.lock` and `pubspec.lock` are committed — be intentional about lockfile changes in diffs.
- The plugin exposes a singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`); don't reintroduce per-instance state without considering the existing global publication lifecycle.
- **Prefer honest limitations over brittle workarounds:** When a platform constraint makes a feature impossible or incomplete, document the limitation clearly rather than reimplementing platform behaviour. Reimplementing system UI (copy semantics, share intents, localised strings, DRM-aware actions) to work around a constraint produces code that is hard to maintain and silently diverges from platform conventions. A clear doc comment is more valuable than a fragile shim.
- **Ask before committing to a solution with obvious downsides:** if a planned approach has significant trade-offs, platform gaps, or multiple reasonable alternatives, surface them to the user with a brief summary of options before implementing. Don't silently pick the path of least resistance — a short "here are the options" saves a revert later.
- **Readium CSS overrides decoration `background-color` — fills MUST be `!important`:** When a custom theme/background is active (the reader effectively always sets one), Readium CSS injects `:root[style*="--USER__backgroundColor"] * { background-color: transparent !important }`, which forces *every* element's background to transparent. Any decoration whose visible effect is its fill (e.g. `highlight`, `ruler`) must declare `background-color: … !important`, or it renders invisibly — this is why the upstream default highlight template uses `!important`. This applies on all three platforms: iOS/Android emit the `!important` directly in the decoration template HTML; on Web the upstream decorator sets only a *plain* inline `background-color`, so `injectDecorationOverrides` re-asserts it as inline `!important` (inline important beats stylesheet important) via a `MutationObserver`. Decorations that don't rely on a fill are immune: `spotlight` works via box-shadow (iOS/Android) or body-dimming `color` CSS (Web), and `underline` swaps the fill for a `border-bottom`.

## Testability (marionette)

- **Launching the app:** Run `flutter run` with `run_in_background: true` (the command never terminates while the app is running). Poll the background task output for `A Dart VM Service ... is available at: <uri>`, extract the URI, then `marionette register <name> <uri>/ws`. Do not use a foreground Bash call — it will always hit the timeout. Poll pattern: `for i in $(seq 1 30); do grep -m1 "Dart VM Service" <output_file> 2>/dev/null && break; sleep 1; done`
- When adding interactive UI elements to the example app that should be exercisable via marionette, add a `ValueKey<String>` to the widget (especially `TextField`s inside `Autocomplete`). This makes `marionette tap --key` and `marionette enter-text --key` reliable.
- Prefer `tap --key` or `tap --text` over coordinate-based taps (`tap --x --y`). Coordinate taps are fragile — elements can overlap or shift between devices, leading to flaky tests that hit the wrong target.
- PDF content does not render visibly in marionette screenshots — marionette captures the Flutter compositing layer, which cannot reach native platform views (PDFKit/PDFium). When you need to visually verify native view content, use `xcrun simctl io booted screenshot /tmp/screen.png` instead (captures the full simulator framebuffer). For routine PDF navigation verification, check `marionette get-logs` for `onPageChanged` locator position.
