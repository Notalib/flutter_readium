# flutter_readium — iOS (Swift)

Thin wrapper over [swift-toolkit](https://github.com/readium/swift-toolkit/); the pinned version lives in two files that must agree: the podspec and `flutter_readium/Package.swift`. Run `bin/readium_versions --check` after any bump — CI runs it too. Repo-wide instructions: `../../AGENTS.md`.

- **Before declaring any Swift changes done:** run `flutter build ios --no-codesign` in `../example` and fix all errors.
- **Gate scope:** for Swift-only changes, the iOS checks are sufficient. Run the repo-wide Dart format/analyze gates only when Dart or shared API files also changed.
- The example app builds with Swift Package Manager. Consuming apps still on CocoaPods must set `use_frameworks!` and `use_modular_headers!` in their `Podfile` (see `docs/getting-started/installation.md`).
- Crash in Swift with only Flutter console output? Ask for a symbolicated Xcode crash report rather than reading further — see Bug investigation in the root file.
