# Make Swift Package Manager the default iOS path

## Why

- The CocoaPods trunk becomes read-only on 2 December 2026. New swift-toolkit releases may not be published there after that date.
- Flutter 3.50 prints a warning on every CLI command while SPM is disabled. A later release removes the opt-out flag, and after that the CocoaPods fallback.
- The plugin already ships `ios/flutter_readium/Package.swift`. Only the example app and CI still use CocoaPods.

## Open question first

The example turned SPM off with `enable-swift-package-manager: false`. The reason is not in git history, because it arrived in the squashed v0.4.4 import. Ask the maintainers before you start. The answer may add a step to this plan.

## Requirements

This needs macOS with Xcode. Flutter rewrites `Runner.xcodeproj` during the first SPM build, so the project changes cannot be written by hand on Linux.

## Steps

1. Remove `config: enable-swift-package-manager: false` from `flutter_readium/example/pubspec.yaml`.
2. Remove the five explicit `pod 'Readium…'` lines from `flutter_readium/example/ios/Podfile`. With SPM on, the Readium packages come from `Package.swift`. Keeping the pods as well links Readium twice. Keep the Podfile itself for any example dependency that still only supports CocoaPods.
3. Run `flutter build ios --no-codesign` in the example. Commit the generated `project.pbxproj` changes and `Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
4. Link the Readium products to the `RunnerTests` target, because the native unit tests import Readium modules. Run the iOS unit tests the same way `.github/workflows/test.yml` does.
5. Update `bin/readium_versions`. The example Podfile no longer pins Readium, so the check covers only the podspec and `Package.swift`. Update the "three files" wording in `AGENTS.md` and `flutter_readium/ios/AGENTS.md` to match.
6. Update CI in `build-ios.yml`, `integration-test-ios.yml` and the `ios-unit-tests` job in `test.yml`. Drop or reduce the `pod install` steps and the Pods caches. Key the DerivedData caches on `Package.resolved`.
7. Update `README.md` and `docs/getting-started/installation.md`. Recommend SPM, and keep the CocoaPods instructions, including `use_frameworks!` and `use_modular_headers!`, as the fallback.
8. Add a changelog fragment for `flutter_readium`, because the recommended install path changes for consumers.

## Done when

- `flutter build ios` and the iOS integration tests pass in CI with SPM on and no Flutter SPM warning.
- `bin/readium_versions --check` passes.
- A fresh app installs the plugin through SPM with no Podfile edits.
