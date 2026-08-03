# flutter_readium

Federated Flutter plugin wrapping the [Readium](https://readium.org) toolkits (EPUB / audiobook / WebPub). One shared Dart API; each platform delegates to its native Readium toolkit. macOS = no-op stub (upstream swift-toolkit has no macOS support). `AGENTS.md` symlinks here. Deep detail lives in `docs/` — pointers inline below.

## Repo layout

- `flutter_readium_platform_interface/` — shared Dart API, models, method-channel contract.
- `flutter_readium/` — app package: native wrappers (iOS/Swift, Android/Kotlin, macOS stub) + web impl (TS → JS bundle in a webview).
  - `example/` — **the smoke-test target.** Verify UI/behavior changes here (via marionette) before declaring done.
- `bin/` — multi-package dev scripts (self-describing; run directly, never `bash -lc`).

## Upstream toolkits

Native sides are thin wrappers — for native behavior the source of truth is upstream. Inspect via `gh api`/`WebFetch`; **never decompile JARs/.framework/build artifacts.** Versions are pinned in the build files (run `bin/readium_versions` to print them), not duplicated here.

- swift-toolkit — https://github.com/readium/swift-toolkit/ (version in podspec + example `Podfile`)
- kotlin-toolkit — https://github.com/readium/kotlin-toolkit/ (`ext.readium_version` in `android/build.gradle`)
- ts-toolkit — npm `@readium/{shared,navigator,navigator-html-injectables}` (`package.json`)
- TTS voice data — https://github.com/readium/speech (refresh: `bin/update_readium_voice_data`)

When upgrading a toolkit, move all three platforms together where API surface overlaps — divergence is a recurring bug source. Architecture: `README.md`, `docs/architecture.md`, `docs/api-reference/`.

## Workflow

- `bin/doctor` — verify toolchain. `bin/install` — full bootstrap after clone / dependency change.
- `bin/update_flutter_version <version>` — update the Flutter SDK minimum version across `.flutter-version` and both pubspecs.
- **Before any PR:** `bin/format` + `bin/analyze` (both cover all three packages); fix everything they report.
- **Before declaring any Swift changes done:** run `flutter build ios --no-codesign` in `flutter_readium/example` and fix all errors.
- **Before declaring any Kotlin changes done:** run `./gradlew :flutter_readium:compileDebugKotlin` in `flutter_readium/example/android/` and fix all errors.
- **Before declaring any web TS changes done:** run `bin/typecheck`, then `bin/update_web_example`. Never hand-edit built JS.
- **Before declaring any `bin/` script changes done:** run `bash -n <script>` for each edited script and fix any syntax errors.
- **Code research**: prefer `tokensave_*` MCP tools over grep/Explore (`.tokensave/`, gitignored; `tokensave sync` after pulling).
- **Branching workflow** — never commit to `main`, and never let a branch track `Notalib/flutter_readium`:
  - Worktree branches created by agents often track upstream `main` — rename and re-track before committing: `git branch -m fix/short-slug && git push -u <fork> HEAD`.
  - Branch names must use a CC prefix: `fix/`, `feat/`, `chore/`, `docs/`, `refactor/`, `test/`.
  - Find the fork remote: `gh api user --jq '.login'` → username matches fork remote name.
  - When done: confirm all changes committed, then open a PR `<fork>:<branch>` → `Notalib/flutter_readium:main`. Confirm with user before pushing.

## Conventions

- **Commits / PR titles**: Conventional Commits with scopes (see `git log`). Include fixed issues in commit desc, e.g. "Fixes #123"
- **Branching**: GitHub flow off `main`; `main` is the only relevant branch.
- **Changelog**: update `CHANGELOG.md` under Unreleased for consumer-visible changes only — exclude intra-PR fixes and example-app changes ("would someone upgrading notice this?").
- **Verification honesty**: don't claim verification you didn't do. If a change can't be exercised in the example app (native-only, behind a flag, platform edge case), say so explicitly.
- **Method-channel contract**: keep Dart (`flutter_readium_platform_interface`) in sync with all native sides. Every call needs a Swift, Kotlin, and web handler — or an explicit `UnimplementedError` if intentionally unsupported.
- **Bridge serialization**: Readium-owned objects (`Locator`, `Decoration`, …) → JSON strings via `json.encode`; plugin-owned flat structures (preferences, action configs) → Maps. Rationale + Web-TS `.serialize()` rules: `docs/architecture.md#bridge-serialization`.
- **Models**: hand-written `toJson`/`fromJson`. No `json_serializable`/`freezed`/build_runner codegen — don't reintroduce.
- **PDF locator**: position = 1-based page in `Locator.locations.position` (matches upstream); don't invent plugin-side parallels to upstream models. Detail: `docs/api-reference/locator.md#pdf-locators`.

### Android

- **Kotlin formatting**: after writing or editing any Kotlin file, run `ktlint --format` on it. All violations must be resolved before committing.
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

- Dart SDK: `>=3.8.0 <4.0.0`. Flutter version pinned in `.flutter-version` (synced to pubspecs via `bin/update_flutter_version`).
- Android: `minSdkVersion 24`, `compileSdk 36`, Kotlin 2.3.21, AGP 8.13.2, Java 18 source/target.
- iOS: requires `use_frameworks!` and `use_modular_headers!` in consuming `Podfile` (see top-level `README.md`).
- Web: webpack 5, TypeScript 5.7+.
- **Flutter version updates**: always update `.flutter-version`, `.fvmrc`, and both pubspec.yaml files (`flutter_readium/pubspec.yaml`, `flutter_readium_platform_interface/pubspec.yaml`) together via `bin/update_flutter_version <version>`. Never change one without the others — divergence causes build failures.

## Gotchas

- Singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`) — no per-instance state; respect the global publication lifecycle.
- `example/`'s `Podfile.lock` + `pubspec.lock` are committed — be intentional about lockfile diffs.
- **Test fixtures are generated, not committed** — `example/assets/pubs/` (native) and `example/web/test-fixtures/` (web) are gitignored, built from the `readium-test-resources` repo by `bin/fetch_test_resources` (run by `bin/install`; CI uses the `fetch-test-resources` action). Missing/stale fixtures? Re-run `bin/fetch_test_resources`. Never hand-edit them; to add/change one, edit the source repo + the matching `trim` line in `bin/build_test_fixtures`. Detail: `CONTRIBUTING.md#test-fixtures`.
- iOS consumers need `use_frameworks!` + `use_modular_headers!` in their `Podfile` (see `README.md`).
- **Decoration fills must be `!important`** — Readium CSS forces all backgrounds transparent under a custom theme. Editing any fill-based decoration (highlight/ruler)? Read `docs/troubleshooting.md#decorations-render-invisibly-fills-must-be-important` first.
- **Honest limitations over brittle workarounds**: document a platform constraint rather than reimplementing system UI (copy/share/localised strings/DRM). Surface trade-offs and ask before committing to an approach with obvious downsides.

## Testing (marionette / web preview)

Example app is the canonical E2E smoke test. Full operational guide: `docs/agent-testing.md`.

- Launch `flutter run` **in background**, poll output for the Dart VM Service URI, then `marionette register`. Never a foreground Bash call (it hits the timeout).
- Add `ValueKey<String>` to interactive widgets; prefer `tap --key`/`--text` over coordinate taps.
- PDF/native views don't render in marionette screenshots — use `xcrun simctl io booted screenshot`, or check `marionette get-logs` for `onPageChanged`.
- Web example: `bin/run_web_example [port]` + `Claude_Preview` MCP. Flutter shell = `<canvas>` (use screenshots); EPUB content = real HTML/iframe (inspect/eval works).
