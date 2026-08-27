# flutter_readium

Federated Flutter plugin wrapping the [Readium](https://readium.org) toolkits (EPUB / audiobook / WebPub). One shared Dart API; each platform delegates to its native Readium toolkit. macOS = no-op stub (upstream swift-toolkit has no macOS support). `AGENTS.md` symlinks here. Platform specifics live in nested `CLAUDE.md` files under `flutter_readium/{ios,android,web}/`, loaded when you touch files there. Deep detail lives in `docs/` — pointers inline below.

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
- `bin/update_flutter_version <version>` — the only way to change the Flutter SDK version. It moves the dev pin (`.flutter-version`, `.fvmrc`, example pubspec) together; changing one by hand causes build failures. The published floor in the two library pubspecs is deliberately separate — raise it only with `--min-sdk`, as a deliberate breaking change, never as a side effect of bumping the SDK we build with.
- **Before any PR:** `bin/format` + `bin/analyze` (both cover all three packages); fix everything they report.
- **Platform build and lint gates** — the checks that must pass before declaring native or web changes done live in the nested platform files: `flutter_readium/ios/CLAUDE.md`, `flutter_readium/android/CLAUDE.md`, `flutter_readium/web/CLAUDE.md`. Read the one for the platform you touch.
- **Before declaring any `bin/` script changes done:** run `bash -n <script>` for each edited script and fix any syntax errors.
- **Branching workflow** — never commit to `main`, and never let a branch track `Notalib/flutter_readium`:
  - Worktree branches created by agents often track upstream `main` — rename and re-track before committing: `git branch -m fix/short-slug && git push -u <fork> HEAD`.
  - Branch names must use a CC prefix: `fix/`, `feat/`, `chore/`, `docs/`, `refactor/`, `test/`.
  - Find the fork remote: `gh api user --jq '.login'` → username matches fork remote name.
  - When done: confirm all changes committed, then open a PR `<fork>:<branch>` → `Notalib/flutter_readium:main`. Confirm with user before pushing.

## Conventions

- **Commits / PR titles**: Conventional Commits with scopes (see `git log`). Include fixed issues in commit desc, e.g. "Fixes #123"
- **Branching**: GitHub flow off `main`; `main` is the only relevant branch.
- **Changelog**: update `CHANGELOG.md` under Unreleased for consumer-visible changes only — exclude intra-PR fixes and example-app changes ("would someone upgrading notice this?"). Keep each entry to a bold one-line lead plus 2–4 lines: symptom, cause in a clause, fix. Cut internal mechanism, field-level detail, and anything restating the lead — a reader upgrading needs to recognise the symptom, not understand the internals. Link to `docs/` when the detail genuinely matters.
- **Comments**: 1–3 lines. Don't narrate the code, and don't inline a rationale essay — that belongs in `docs/`. Brevity means cutting content, not compressing prose: write plain sentences, never telegraphese. Never prefix a comment with the tool, skill, or agent that produced it — that's noise. Say only what the code can't: a non-obvious constraint, why the simpler thing doesn't work, or a cross-reference.
- **Verification honesty**: don't claim verification you didn't do. If a change can't be exercised in the example app (native-only, behind a flag, platform edge case), say so explicitly.
- **Method-channel contract**: keep Dart (`flutter_readium_platform_interface`) in sync with all native sides. Every call needs a Swift, Kotlin, and web handler — or an explicit `UnimplementedError` if intentionally unsupported.
- **Bridge serialization**: Readium-owned objects (`Locator`, `Decoration`, …) → JSON strings via `json.encode`; plugin-owned flat structures (preferences, action configs) → Maps. Rationale + Web-TS `.serialize()` rules: `docs/architecture.md#bridge-serialization`.
- **Models**: hand-written `toJson`/`fromJson`. No `json_serializable`/`freezed`/build_runner codegen — don't reintroduce.
- **PDF locator**: position = 1-based page in `Locator.locations.position` (matches upstream); don't invent plugin-side parallels to upstream models. Detail: `docs/api-reference/locator.md#pdf-locators`.
- **copyWith sentinel**: use the shared `const unset` from `utils/constants.dart` for parameters that default to "not set" — never declare a new `_unset = Object()`. Merge additional-properties via `AdditionalProperties.copyAdditionalProperties()` instead of inline merge logic.

## Build / toolchain facts

- Dart SDK: `>=3.8.0 <4.0.0`. Flutter version pinned in `.flutter-version` — see the Workflow note above before changing it.
- Per-platform toolchain facts (Android SDK/Kotlin/AGP levels, iOS `Podfile` requirements, the web bundler) live in the nested platform files.

## Gotchas

- Singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`) — no per-instance state; respect the global publication lifecycle.
- `example/`'s `Podfile.lock` + `pubspec.lock` are committed — be intentional about lockfile diffs.
- **Test fixtures are generated, not committed** — `example/assets/pubs/` (native) and `example/web/test-fixtures/` (web) are gitignored, built from the `readium-test-resources` repo by `bin/fetch_test_resources` (run by `bin/install`; CI uses the `fetch-test-resources` action). Missing/stale fixtures? Re-run `bin/fetch_test_resources`. Never hand-edit them; to add/change one, edit the source repo + the matching `trim` line in `bin/build_test_fixtures`. Detail: `CONTRIBUTING.md#test-fixtures`.
- **Decoration fills must be `!important`** — Readium CSS forces all backgrounds transparent under a custom theme. Editing any fill-based decoration (highlight/ruler)? Read `docs/troubleshooting.md#decorations-render-invisibly-fills-must-be-important` first.
- **Honest limitations over brittle workarounds**: document a platform constraint rather than reimplementing system UI (copy/share/localised strings/DRM). Surface trade-offs and ask before committing to an approach with obvious downsides.

## Bug investigation

Stop reading code and ask the user for a crash report, screenshot, or Xcode/Android Studio run when any of these apply:
- Crash is in native code but you only have Flutter console output — a symbolicated stack trace (Xcode crash report, `adb logcat`) gives thread state and exact crash site.
- 2+ competing hypotheses and you can't falsify them statically — runtime state is the arbiter.
- You've opened ~8+ files without converging on a hypothesis.
- Crash involves async ordering or threading — static analysis can't reveal this.
- You've reached Pods, `build/`, or compiled artifacts — ask for symbolicated output instead.

## Testing (marionette / web preview)

Example app is the canonical E2E smoke test. Full operational guide: `docs/agent-testing.md`.

- Launch `flutter run` **in background**, poll output for the Dart VM Service URI, then `marionette register`. Never a foreground Bash call (it hits the timeout).
- Add `ValueKey<String>` to interactive widgets; prefer `tap --key`/`--text` over coordinate taps.
- PDF/native views don't render in marionette screenshots — use `xcrun simctl io booted screenshot`, or check `marionette get-logs` for `onPageChanged`.
- Web example runs in a browser instead — see `flutter_readium/web/CLAUDE.md`.

## Claude Code specifics

Other tools read this file too — Copilot supports `CLAUDE.md` directly, and `AGENTS.md` symlinks here. This section is Claude Code only; skip it otherwise.

- **Code research**: prefer `tokensave_*` MCP tools over grep/Explore (`.tokensave/`, gitignored; `tokensave sync` after pulling). When plan mode asks for exploration agents, do the tokensave sweep in the main loop and spawn Explore only for breadth tokensave can't cover — docs, web, external APIs.
- **Tokensave freshness (repo-local only)**: run `bin/tokensave_sync_if_needed` after pulls/rebases/branch switches and before large exploration sessions. On a stale index, run it once and retry `tokensave_*` before falling back to grep/read tools.
- **Web preview**: the `Claude_Preview` MCP drives the web example; the browser-side detail is in `flutter_readium/web/CLAUDE.md`.
