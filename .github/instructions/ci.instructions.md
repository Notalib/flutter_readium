---
description: CI/CD conventions and pitfalls for flutter_readium GitHub Actions workflows.
applyTo: '.github/workflows/*.yml'
---

# CI/CD Conventions

## Caching

All workflows that build iOS or Android must include the relevant caches:

- **Android**: Cache `~/.gradle/caches` and `~/.gradle/wrapper`, keyed on the relevant `build.gradle` files. Include a `restore-keys` prefix fallback.
- **iOS (CocoaPods)**: Cache `flutter_readium/example/ios/Pods` and `~/.cocoapods`, keyed on `Podfile.lock`. `~/.cocoapods` is required — it holds the trunk spec repo used to resolve Flutter ecosystem pods (e.g. webview_flutter). Without it, a cold `pod install` fails even though Readium pods use explicit `podspec:` URLs.
- **iOS (Xcode derived data)**: Cache `~/Library/Developer/Xcode/DerivedData`, keyed on `Podfile.lock`.
- **Android emulator AVD**: Cache `~/.android/avd/*` and `~/.android/adb*`, keyed on API level.

Cache keys must end with a trailing dash before the hash segment (e.g. `gradle-${{ runner.os }}-`) to prevent accidental prefix collisions between keys that share a common prefix.

## CocoaPods `--repo-update`

Only pass `--repo-update` when the CocoaPods cache is cold (cache miss). On a cache hit the spec repo is already in `~/.cocoapods` and the flag just wastes ~30s. Use the `cache-hit` output from the pods cache step.

## Permissions

The release workflow needs `permissions: contents: write` on the job to allow `softprops/action-gh-release` to create releases. This is already the minimum — GitHub does not offer a narrower "releases only" scope. Also set `fetch-depth: 0` on the checkout step so all tags are available (needed for the manual-dispatch tag verification).

## Release workflow: manual dispatch

The release workflow supports both tag-push and `workflow_dispatch` triggers. On manual dispatch, `GITHUB_REF_NAME` is the branch name, not a tag. The version must be read from `flutter_readium/pubspec.yaml` and the corresponding tag verified to exist via `git rev-parse`.

## Release preparation

Use `bin/prepare-release <version>` before tagging. It:
1. Bumps `version:` in both pubspec files
2. Moves `## Unreleased` content into a dated `## [x.y.z] - YYYY-MM-DD` section
3. Leaves a fresh `## Unreleased` header

Do not automate this in the CI pipeline — the changelog rewrite should be in the tagged commit itself, not a commit pushed by the workflow after tagging.

## Integration vs build workflows

`flutter test integration_test` performs its own build internally (targeting the emulator/simulator) and cannot consume a pre-built APK/app from the build workflows. Don't couple the integration-test workflow to the build workflows — they serve different purposes. Share only caching patterns.
