# Plan: Document and script Flutter version updates

## Discovery findings
- `.flutter-version` exists at repo root with value `3.44.4`
- All 11 GitHub workflows already read from it via `cat .flutter-version` steps
- CI instructions (`.github/instructions/ci.instructions.md`) document *how* workflows consume it, but not that users should update it
- README.md "Minimum requirements" table says Flutter 3.32.0+ (outdated vs pubspec's 3.44.0)
- CLAUDE.md Build/toolchain facts says `Flutter >=3.44.0` (correct but not linked to `.flutter-version`)
- `flutter_readium/pubspec.yaml` has `flutter: '>=3.44.0'` in environment

## Alignment decisions
- Script name: `bin/update_flutter_version` (clear, consistent with existing naming)
- Initial `.flutter-version` value: already `3.44.4`, script should accept a version argument

## Design

**Steps**
1. **Create `bin/update_flutter_version <version>`** — modeled after `bin/prepare-release` pattern:
   - Sources `_common.sh` for `REPO_ROOT`
   - Validates semver input (e.g., `3.45.0`)
   - Writes version to `.flutter-version` (single line)
   - Updates `flutter_readium/pubspec.yaml` `environment.flutter` from `'>=X.Y.Z'` to `'>=A.B.C'` using the provided version as the new minimum
   - Prints summary of changes made

2. **Update README.md** "Minimum requirements" section:
   - Change Flutter row from `3.32.0+` → reference `.flutter-version` as source of truth (currently stale — says 3.32.0 but pubspec says 3.44.0)
   - Add a note for contributors pointing to `bin/update_flutter_version`

3. **Update CLAUDE.md**:
   - In the Workflow section, add `bin/update_flutter_version <version>` alongside existing bin scripts (`bin/doctor`, `bin/install`, etc.)
   - In Build/toolchain facts, clarify that the Flutter version is pinned in `.flutter-version` and synced to pubspec via the script

**Relevant files**
- `bin/update_flutter_version` — **new file**, modeled after `bin/prepare-release` pattern (source `_common.sh`, argument parsing, validation)
- `README.md` — "Minimum requirements" table + note about `.flutter-version`
- `CLAUDE.md` — Workflow section (add script to bin list), Build/toolchain facts (link to `.flutter-version`)

**Verification**
1. `bash -n bin/update_flutter_version` — syntax check
2. Run `bin/update_flutter_version 3.45.0` and verify:
   - `.flutter-version` contains `3.45.0`
   - `flutter_readium/pubspec.yaml` has `flutter: '>=3.45.0'`
   - Revert back to `3.44.4` / `>=3.44.0`
3. `bin/format && bin/analyze` — no regressions from doc changes

**Decisions**
- Script takes a single positional argument (the new Flutter version, e.g., `3.45.0`) — not a constraint string like `>=3.45.0`. The script constructs the pubspec constraint.
- Only updates `flutter_readium/pubspec.yaml`, NOT `flutter_readium_platform_interface/pubspec.yaml` — the platform interface inherits the same SDK constraint from the plugin's dependency, and changing it would require separate consideration. (User only mentioned `flutter_readium/pubspec.yaml`.)
- `.flutter-version` is the single source of truth for CI; pubspec minimum is derived by the script.

**Further Considerations**
1. Should the script also update `flutter_readium_platform_interface/pubspec.yaml`'s `environment.flutter`? Currently it's separate — worth confirming before implementing.
2. The README.md "Minimum requirements" table currently says 3.32.0+ which is stale. Should we also fix this discrepancy as part of the same PR, or keep it scoped to documentation additions only?