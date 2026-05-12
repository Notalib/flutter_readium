---
description: Regenerate json_serializable model code and report any unexpected diffs
---

Run code generation for the platform interface package, then verify the result.

Steps:

1. Run `bin/code_gen` from the repo root. This invokes `dart run build_runner build --delete-conflicting-outputs` inside `flutter_readium_platform_interface/`.
2. After it completes, run `git status -- flutter_readium_platform_interface/` to see which generated files changed.
3. For each changed `*.g.dart` file, briefly summarize whether the diff looks intentional (matches recent edits to the corresponding `@JsonSerializable()` model) or unexpected.
4. If any non-generated file shows up as changed, flag it — codegen should only touch `*.g.dart` outputs.
5. Don't commit anything. Report the summary back to the user so they can decide.

Notes:
- The platform interface is the only package with `build_runner` configured — the app-facing `flutter_readium` package doesn't need codegen.
- If `bin/code_gen` fails, do not retry blindly. Report the error and stop.
