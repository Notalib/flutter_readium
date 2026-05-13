# flutter_readium

A Flutter plugin wrapping the [Readium](https://readium.org) toolkits for EPUB / audiobook / WebPub reading. The Dart API is shared across iOS, macOS, Android, and Web; each platform delegates to the matching native Readium toolkit.

## Repo layout

This is a **federated Flutter plugin** with two pub packages and a multi-package root:

- `flutter_readium_platform_interface/` — shared Dart API, models (hand-written `toJson`/`fromJson`), method-channel contract. Both the app-facing package and any future platform implementations depend on this. Entry point: `lib/flutter_readium_platform_interface.dart`; channel impl in `lib/method_channel_flutter_readium.dart`.
- `flutter_readium/` — the app-facing package. Bundles the native wrappers and the web implementation:
  - `lib/` — Dart entry points (`flutter_readium.dart`, `reader_widget*.dart`). `reader_widget_switch.dart` dispatches to the native platform view or the web webview.
  - `ios/flutter_readium/Sources/flutter_readium/` — Swift wrapper around **swift-toolkit**. Plugin entry: `FlutterReadiumPlugin.swift`; channel handler: `ReadiumReaderChannel.swift`; platform view: `ReadiumReaderView{,Factory}.swift`.
  - `android/src/main/kotlin/dk/nota/` — Kotlin wrapper around **kotlin-toolkit**. Android package id: `dk.nota.flutter_readium`.
  - `macos/` — macOS plugin (shares Swift sources with iOS where possible).
  - `web/` — Web implementation in TypeScript that compiles to a JS bundle loaded inside a webview. Webpack config at `web/_scripts/webpack.config.js`.
  - `assets/_helper_scripts/` — separate TypeScript helpers injected into the webview at runtime (built by `flutter_readium/bin/build_helper_scripts.sh`).
  - `example/` — **the smoke-test target.** All UI / behavior changes should be verified by running the example app before declaring a task done.
- `bin/` (repo root) — multi-package developer scripts (see below).

## Upstream Readium toolkits

The native sides are thin wrappers around upstream Readium code — when debugging native behavior, the source of truth is upstream:

- swift-toolkit: https://github.com/readium/swift-toolkit/ — pinned to **3.7.0** in `flutter_readium/ios/flutter_readium.podspec` and the example `Podfile`.
- kotlin-toolkit: https://github.com/readium/kotlin-toolkit/ — pinned to **3.1.2** via `ext.readium_version` in `flutter_readium/android/build.gradle`.
- ts-toolkit (Web): consumed via npm — `@readium/shared`, `@readium/navigator`, `@readium/navigator-html-injectables` (see `flutter_readium/package.json`).

Voice data for TTS comes from https://github.com/readium/speech (refreshed by `bin/update_readium_voice_data`).

When upgrading any toolkit version, check that all three platforms move together where API surface overlaps — divergence between platforms is a recurring source of bugs. Also update every version reference in the docs and README to match the new pinned version, to avoid drift.

## Developer workflow

Repo-root scripts (`bin/*`) — run from the repo root:

- `bin/install` — bootstrap everything: `pub get` in both packages, `pod update && pod install` for the example, build helper scripts, build web JS, copy JS into example. Run after a fresh clone or when dependencies change.
- `bin/forAll <cmd>` — run a command in both pub packages. Example: `bin/forAll dart pub upgrade`.
- `bin/build_js` — build the web bundle (currently `build_dev`; production build is commented out).
- `bin/update_web_example` — `build_js` + copy the bundle into `flutter_readium/example/web/`. Run after editing TS in `flutter_readium/web/`.
- `bin/update_readium_voice_data` — refresh `flutter_readium/assets/voice_data/voices.json` from the upstream `readium/speech` repo (requires `jq`).

Plugin-local script:

- `flutter_readium/bin/build_helper_scripts.sh` — builds the `_helper_scripts` TS bundle that is injected into the webview.

Running the example app: `cd flutter_readium/example && flutter run`. For web specifically, ensure `bin/update_web_example` has been run after any TS change.

## Conventions

- **Commits**: use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `refactor:`, scopes like `feat(example): …` are common — see `git log`). PR titles should follow the same format.
- **Branching**: GitHub flow — short-lived feature branches off `main`. `main` is the only relevant branch; any older branches in the repo are historical and should be ignored.
- **Smoke test**: the example app at `flutter_readium/example/` is the canonical end-to-end smoke test. If a change can't be exercised in the example, say so explicitly rather than claiming it's verified.
- **Models & method-channel contract**: keep the Dart side in `flutter_readium_platform_interface` in sync with both native implementations. If you add a method-channel call, all three native sides (Swift, Kotlin, web) need a matching handler — or an explicit `UnimplementedError` if intentionally unsupported.
- **Models**: serialise with hand-written `toJson` / `fromJson` methods. The project no longer uses `json_serializable` or `freezed` code generation — don't reintroduce build_runner-based codegen.
- **Web JS**: don't hand-edit the built JS in `example/web/`. Edit TS sources, then `bin/update_web_example`.

## Build / toolchain facts

- Dart SDK: `>=3.8.0 <4.0.0`, Flutter `>=3.3.0`.
- Android: `minSdkVersion 24`, `compileSdk 36`, Kotlin 2.2.20, AGP 8.13.0, Java 18 source/target.
- iOS: requires `use_frameworks!` and `use_modular_headers!` in consuming `Podfile` (see top-level `README.md`).
- Web: webpack 5, TypeScript 5.7+.

## Gotchas

- The example app's `Podfile.lock` and `pubspec.lock` are committed — be intentional about lockfile changes in diffs.
- Android consumers must extend `FlutterFragmentActivity` (not `FlutterActivity`), otherwise the reader view crashes at runtime.
- The plugin exposes a singleton API (`FlutterReadium()` in `lib/flutter_readium.dart`); don't reintroduce per-instance state without considering the existing global publication lifecycle.
- The plugin currently targets EPUB / WebPub (with or without pre-recorded audio); LCP and PDF adapter code is present-but-commented in `android/build.gradle` — don't enable it without a deliberate plan.
