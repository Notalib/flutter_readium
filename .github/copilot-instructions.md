# flutter_readium

> This file is derived from `CLAUDE.md` and intentionally condensed for Copilot. Keep behavior/tooling guidance in sync with `CLAUDE.md`.

A Flutter plugin wrapping the [Readium](https://readium.org) toolkits for EPUB / audiobook / WebPub reading. The Dart API is shared across iOS, Android, and Web; each platform delegates to the matching native Readium toolkit. macOS registers a no-op stub only — native macOS is unsupported by upstream swift-toolkit.

## Architecture

Federated Flutter plugin with two pub packages:

- `flutter_readium_platform_interface/` — shared Dart models, method-channel contract, abstract platform interface.
- `flutter_readium/` — app-facing package with native wrappers (iOS/Swift, Android/Kotlin, macOS stub) and a TypeScript→JS web implementation.
  - `flutter_readium/example/` — canonical smoke-test app. Verify all UI/behavior changes here before declaring a task done.

Data flow:
```
FlutterReadium (singleton)
  → FlutterReadiumPlatform (abstract)
    → MethodChannelFlutterReadium
        ├── iOS: Swift / swift-toolkit
        ├── Android: Kotlin / kotlin-toolkit
        └── Web: TypeScript / @readium/navigator (in webview via postMessage)
```

Channels defined in `MethodChannelFlutterReadium`:
- **Method channel** `flutter_readium` — request/response (open, navigate, preferences, …)
- **Event channels** (native→Dart): `flutter_readium/reader_status`, `flutter_readium/text_locator`, `flutter_readium/timebased_state`, `flutter_readium/error_event`

Upstream toolkits (source of truth for native behavior — read on GitHub, don't decompile artifacts):
- iOS: https://github.com/readium/swift-toolkit/ (pinned in `flutter_readium/ios/flutter_readium.podspec`)
- Android: https://github.com/readium/kotlin-toolkit/ (pinned via `ext.readium_version` in `flutter_readium/android/build.gradle`)
- Web: `@readium/*` npm packages (see `flutter_readium/package.json`)

## Commands

Run all scripts from the repo root unless noted.

| Command | Purpose |
|---------|---------|
| `bin/install` | Bootstrap: `pub get`, CocoaPods install, build web JS. Run after clone or dependency changes. |
| `bin/format` | Check Dart formatting across all three packages. Fails on any reformatting needed. |
| `bin/analyze` | `dart analyze --fatal-infos --fatal-warnings` across all packages. |
| `bin/update_web_example` | Build TS → JS and copy into `example/web/`. Run after editing TypeScript. |
| `bin/prepare-release <version>` | Bump versions, move Unreleased changelog entries, leave fresh Unreleased header. |

**Run before any PR:** `bin/format && bin/analyze`

### Tests

```bash
# Unit tests (platform interface)
cd flutter_readium_platform_interface && flutter test

# Unit tests (plugin)
cd flutter_readium && flutter test

# Single test file
cd flutter_readium && flutter test test/some_test.dart

# Integration tests (requires booted simulator/emulator)
cd flutter_readium/example
flutter test integration_test --device-id=<udid>   # iOS
flutter test integration_test                      # Android
```

## Key Conventions

### Models & serialization

- Models use hand-written `toJson` / `fromJson` (via `JSONable` mixin). **Do not reintroduce `json_serializable` or `freezed` / build_runner codegen.**
- **Method channel serialization**: Readium-owned objects (`Locator`, `Decoration`, etc.) cross the bridge as **JSON strings** via `json.encode`. Plugin-owned flat structures use Maps/Dictionaries.

### Method channel contract

When adding a method-channel call, all three native sides (Swift, Kotlin, web) need a matching handler — or an explicit `UnimplementedError`. Undocumented silence looks like a bug.

### Singleton pattern

`FlutterReadium` is a singleton with one reader active at a time. Don't introduce per-instance state without reviewing the existing global publication lifecycle.

### PDF locators

PDF position lives in `Locator.locations.position` as a **1-based page number**. Don't invent plugin-side parallel models — use the upstream representation and round-trip via `goToLocator`.

### Changelog & commits

- Update `CHANGELOG.md` for every feature or bugfix. New entries go under `## Unreleased`.
- [Conventional Commits](https://www.conventionalcommits.org/) with scopes: `feat(android):`, `fix(ios):`, `chore(example):`, etc. Branch off `main`.

> Platform-specific conventions (Android log format, navigator null guard, TypeScript locator serialization) are in the scoped instruction files under `.github/instructions/`.

## Code search (tokensave)

This repo is indexed by [tokensave](https://github.com/aovestdipaperino/tokensave) (`.tokensave/`, gitignored). For codebase research — finding symbols, callers/callees, impact — prefer the `tokensave_*` MCP tools (`tokensave_context`, `tokensave_search`, `tokensave_callers`, `tokensave_callees`, `tokensave_impact`, `tokensave_node`, `tokensave_files`, `tokensave_affected`) over grep/glob/Explore; they answer from the semantic graph at a fraction of the tokens. Fall back to direct reads/grep when tokensave is unavailable or a raw text match is genuinely the better tool (e.g. the built JS bundles, which are excluded from the index). Exclusions live in `.tokensave/config.json`; after pulling source changes, run `tokensave sync` to refresh.

## MCP Servers

MCP servers are configured in `.mcp.json`:

**`dart`** — Dart tooling daemon. Prefer its tools over raw bash for Dart/Flutter work:
- `dart-run_tests` instead of `flutter test` in bash — structured pass/fail output, supports filtering by name
- `dart-analyze_files` instead of `dart analyze` — targeted per-file analysis
- `dart-dart_format` / `dart-dart_fix` — format or auto-fix specific files
- `dart-resolve_workspace_symbol` — find symbols by name (fuzzy) across all packages
- `dart-hover` — type info and docs at a cursor position
- `dart-pub` — `add`, `remove`, `get`, `upgrade` without leaving the tool interface

**`marionette`** — Flutter app remote control (requires a running example app). Use for all smoke testing:
- `marionette-connect` first (with the VM service URI from `flutter run` output, suffixed with `/ws`)
- `marionette-take_screenshots` — capture current visual state
- `marionette-get_interactive_elements` — discover tappable widgets and their keys
- `marionette-tap` / `marionette-enter_text` — interact with UI elements
- `marionette-get_logs` — read Flutter logs from the running app
- `marionette-hot_reload` / `marionette-hot_restart` — apply code changes without restarting

**`context7`** — docs retrieval for library/framework/API references. Use it proactively when work depends on Readium/Flutter APIs or examples.

## Smoke Testing (marionette)

Run the example app in the background — `flutter run` never terminates:

```bash
# Start app (async, background)
flutter run  # poll output for "A Dart VM Service ... is available at: <uri>"
# Connect marionette
marionette register <name> <uri>/ws
```

- Prefer `tap --key` / `tap --text` over coordinate taps (fragile).
- Add `ValueKey<String>` to interactive widgets in the example app for reliable marionette targeting.
- PDF content is invisible to marionette screenshots (native platform view). Use `xcrun simctl io booted screenshot /tmp/screen.png` for visual verification; check `marionette get-logs` for `onPageChanged` locator position.
