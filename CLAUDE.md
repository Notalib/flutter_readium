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
- **Before any PR:** `bin/format` + `bin/analyze` (both cover all three packages); fix everything they report.
- **After editing web TS (`flutter_readium/web/`):** `bin/typecheck`, then `bin/update_web_example`. Never hand-edit built JS.
- Code research: prefer `tokensave_*` MCP tools over grep/Explore (`.tokensave/`, gitignored; `tokensave sync` after pulling).

## Conventions

- **Commits / PR titles**: Conventional Commits with scopes (see `git log`).
- **Branching**: GitHub flow off `main`; `main` is the only relevant branch.
- **Changelog**: update `CHANGELOG.md` under Unreleased for consumer-visible changes only — exclude intra-PR fixes and example-app changes ("would someone upgrading notice this?").
- **Verification honesty**: don't claim verification you didn't do. If a change can't be exercised in the example app (native-only, behind a flag, platform edge case), say so explicitly.
- **Method-channel contract**: keep Dart (`flutter_readium_platform_interface`) in sync with all native sides. Every call needs a Swift, Kotlin, and web handler — or an explicit `UnimplementedError` if intentionally unsupported.
- **Bridge serialization**: Readium-owned objects (`Locator`, `Decoration`, …) → JSON strings via `json.encode`; plugin-owned flat structures (preferences, action configs) → Maps. Rationale + Web-TS `.serialize()` rules: `docs/architecture.md#bridge-serialization`.
- **Models**: hand-written `toJson`/`fromJson`. No `json_serializable`/`freezed`/build_runner codegen — don't reintroduce.
- **PDF locator**: position = 1-based page in `Locator.locations.position` (matches upstream); don't invent plugin-side parallels to upstream models. Detail: `docs/api-reference/locator.md#pdf-locators`.

### Android

- After editing any Kotlin file: `ktlint --format`; resolve all violations before committing.
- Every `PluginLog.*` message starts with `::functionName` (exact enclosing named function).
- Navigator-dependent `suspend` funcs: capture `navigator` as a local with a `?: run { … return }` guard, then wrap calls in `return withContext(coroutineContext) { }`. Funcs that only delegate to other wrappers skip the guard.

## Gotchas

- Singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`) — no per-instance state; respect the global publication lifecycle.
- `example/`'s `Podfile.lock` + `pubspec.lock` are committed — be intentional about lockfile diffs.
- iOS consumers need `use_frameworks!` + `use_modular_headers!` in their `Podfile` (see `README.md`).
- **Decoration fills must be `!important`** — Readium CSS forces all backgrounds transparent under a custom theme. Editing any fill-based decoration (highlight/ruler)? Read `docs/troubleshooting.md#decorations-render-invisibly-fills-must-be-important` first.
- **Honest limitations over brittle workarounds**: document a platform constraint rather than reimplementing system UI (copy/share/localised strings/DRM). Surface trade-offs and ask before committing to an approach with obvious downsides.

## Testing (marionette / web preview)

Example app is the canonical E2E smoke test. Full operational guide: `docs/agent-testing.md`.

- Launch `flutter run` **in background**, poll output for the Dart VM Service URI, then `marionette register`. Never a foreground Bash call (it hits the timeout).
- Add `ValueKey<String>` to interactive widgets; prefer `tap --key`/`--text` over coordinate taps.
- PDF/native views don't render in marionette screenshots — use `xcrun simctl io booted screenshot`, or check `marionette get-logs` for `onPageChanged`.
- Web example: `bin/run_web_example [port]` + `Claude_Preview` MCP. Flutter shell = `<canvas>` (use screenshots); EPUB content = real HTML/iframe (inspect/eval works).
