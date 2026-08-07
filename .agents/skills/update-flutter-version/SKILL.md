---
name: update-flutter-version
description: Use bin/update_flutter_version to update the Flutter SDK minimum version across the repo. Activates when the user asks to update the Flutter version, change the Flutter SDK constraint, or mentions .flutter-version / .fvmrc / pubspec flutter constraints.
---

When the user wants to update the Flutter SDK version, use `bin/update_flutter_version <version>` instead of manually editing files.

## How to Use This Skill

### Step 1: Validate the version

Ensure the requested version is valid semver (`X.Y.Z`). If the user provides an invalid format, ask for clarification.

### Step 2: Run the script

```bash
bin/update_flutter_version <version>
```

This updates all four files atomically:

1. `.flutter-version` — CI source of truth
2. `.fvmrc` — FVM config
3. `flutter_readium/pubspec.yaml` — environment.flutter constraint
4. `flutter_readium_platform_interface/pubspec.yaml` — environment.flutter constraint

### Step 3: Bootstrap dependencies

Run `bin/install` to fetch updated dependencies and lockfiles.

## When NOT to Use This Skill

- If the user only wants to check the current Flutter version (use `cat .flutter-version`)
- If the user wants to update the Dart SDK version instead (different script/changes)
