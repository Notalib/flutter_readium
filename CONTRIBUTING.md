# Contributing to flutter_readium

Thank you for considering a contribution! This guide covers everything you need to go from a fresh clone to a passing build.

---

## Prerequisites

| Tool | Minimum version | Notes |
|------|----------------|-------|
| Flutter SDK | 3.32.0 | Stable channel recommended |
| Dart SDK | 3.8.0 | Bundled with Flutter |
| Xcode | 15+ | macOS / iOS targets |
| CocoaPods | 1.15+ | `gem install cocoapods` |
| Android Studio / JDK | Java 18 | `compileSdk 36` |
| Node.js | 18+ | Web TypeScript build only |

---

## Cloning and bootstrapping

```bash
git clone https://github.com/notalib/flutter_readium.git
cd flutter_readium

# Install all pub dependencies, run pod install, and build the web JS bundle
bin/install
```

Setup script `bin/install` does the following in order:

1. `flutter pub get` in both `flutter_readium/` and `flutter_readium_platform_interface/`
2. `pod update && pod install` for the iOS example app
3. Builds the `assets/_helper_scripts` TypeScript bundle
4. Builds the web JS bundle and copies it into `example/web/`

If you only change Dart code you can skip the full install and just run `flutter pub get` in the affected package.

---

## Repo layout

This is a **federated Flutter plugin** with two pub packages:

- `flutter_readium_platform_interface/` — shared Dart models, method-channel contract, and platform API surface
- `flutter_readium/` — app-facing package; bundles native wrappers (iOS, macOS, Android) and the web implementation
- `flutter_readium/example/` — smoke-test app; use this to verify UI changes

---

## Running the example app

```bash
# First run install script from project root
./bin/install

# Then go to the example app folder and run
cd flutter_readium/example
flutter run                   # for native platforms, pick a device when prompted
flutter run -d chrome         # for web platform
```

For web, make sure you run `bin/update_web_example` after any TypeScript change.

---

## Running tests

```bash
# Platform interface unit tests
cd flutter_readium_platform_interface && flutter test

# Plugin unit tests
cd flutter_readium && flutter test
```

### Integration tests

End-to-end tests that exercise the Dart → native → Dart contract live under [flutter_readium/example/integration_test/](flutter_readium/example/integration_test/).

Run them against a booted simulator/emulator or attached device:

```bash
cd flutter_readium/example

# iOS — pick a booted simulator UDID via `xcrun simctl list devices`
flutter test integration_test --device-id=<udid>

# Android — start an emulator or attach a device first
flutter test integration_test
```

The same suite runs in CI on every push/PR via [.github/workflows/integration-test.yml](.github/workflows/integration-test.yml) on an iOS simulator and Android emulators. Feel free to add relevant integration tests, especially when implementing new features and use-cases.

---

## Building the web bundle

After editing TypeScript files in `flutter_readium/web/_scripts/` or `flutter_readium/assets/_helper_scripts/src/`:

```bash
bin/update_web_example   # build + copy into example/web/
```

Do **not** hand-edit the compiled JS in `example/web/`.

---

## Code style

- **Dart** — format with `dart format .` and lint with `flutter analyze`. The CI gate uses `--fatal-infos --fatal-warnings`.
- **Kotlin** — `ktlint` formatting applied via the Android Gradle task. Run `./gradlew ktlintFormat` in `flutter_readium/android/`.
- **Swift** — follows the swift-toolkit conventions; no additional formatter is enforced.
- **TypeScript** — ESLint (`npm run lint` in the relevant directory).
- **Commits** — use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `chore:`, `refactor:`. Scopes are encouraged, e.g. `fix(android):`, `feat(iOS):`, `feat(example):`.

---

## Pull request process

1. Branch off `main` with a short, descriptive name (e.g. `fix/android-progression`).
2. Keep PRs focused on a single logical change.
3. Ensure `flutter analyze` and both test suites pass locally before opening a PR.
4. Test changes in the example app on at least one platform.
5. Update `CHANGELOG.md` in the affected package(s) under the current unreleased version.
6. Update relevant documentation in the [docs](./docs/) folder if necessary.
7. Use a Conventional Commits PR title — GitHub Actions and the release workflow depend on it.

---

## Filing issues

Please use the [GitHub issue tracker](https://github.com/notalib/flutter_readium/issues). Include:

- Flutter version (`flutter --version`)
- Target platform and OS/device
- Observed vs. expected behavior
- Minimal reproduction steps or a code snippet
- Logcat / Xcode console / stacktrace output if relevant

---

## License

By contributing you agree that your contributions will be licensed under the [BSD 3-Clause License](LICENSE).
