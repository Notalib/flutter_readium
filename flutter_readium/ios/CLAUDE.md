# flutter_readium — iOS (Swift)

Thin wrapper over [swift-toolkit](https://github.com/readium/swift-toolkit/); the pinned version lives in three files that must agree: the podspec, `flutter_readium/Package.swift`, and the example `Podfile`. Run `bin/readium_versions --check` after any bump — CI runs it too. Repo-wide instructions: `../../CLAUDE.md`.

- **Before declaring any Swift changes done:** run `flutter build ios --no-codesign` in `../example` and fix all errors.
- Consuming apps must set `use_frameworks!` and `use_modular_headers!` in their `Podfile` (see the top-level `README.md`).
- Crash in Swift with only Flutter console output? Ask for a symbolicated Xcode crash report rather than reading further — see Bug investigation in the root file.
