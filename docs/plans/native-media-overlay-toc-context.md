# Native media-overlay ToC context implementation tasks

**Decision:** [ADR 0001](../adr/0001-native-media-overlay-toc-ownership.md).
**Branch:** `fix/media-overlay-toc-context`, from main `c3b2225`.
> **Published in [PR #274](https://github.com/Notalib/flutter_readium/pull/274).** Current test totals and focused integration coverage are in the [ADR 0001 regression record](media-overlay-adr-regressions.md); the earlier validation table below is retained as historical context.

## Task 1 — Revise the decision from fixture evidence

- [x] Inspect current fixture sources and the related PRs.
- [x] Preserve parent inheritance and flat narrated-heading continuation.
- [x] Replace unconditional cross-file inheritance with resource-aware ownership.
- [x] Define nested-list continuation and same-file anchored-seek behavior explicitly.
- [x] Defer extra navigation indices and audio-less-flat-heading behavior.

## Task 2 — Capture equivalent native regressions

- [x] Add Swift and Kotlin tests for audio-less parent inheritance.
- [x] Demonstrate the synthetic subsection-reset failure before fixing it.
- [x] Demonstrate the cross-file boundary failure using the existing fixture shape.
- [x] Cover a new resource without a file-only ToC entry, recursion boundaries and cue order.
- [x] Cover known structural anchors, exact-anchor/time priority, repeated ids across files,
      and unknown-anchor no-rewind behavior.
- [x] Test title enrichment without reopening a global ownership window.

Swift tests belong in the existing registered `FlutterMediaOverlayTests.swift`.
Kotlin tests belong under `android/src/test/kotlin/dk/nota/flutterreadium/models/`.
Use tiny JSON inputs matching observed shapes; label the mixed parent/subsection case as
synthetic. No new fixture framework or generated-asset edits are needed.

## Task 3 — Fix ownership in Swift and Kotlin

- [x] Parse with local sibling continuation, preserving direct heading matches.
- [x] Bound inheritance by text resource, including fragmentless ToC targets.
- [x] Preserve recursion, timing, duration, position and original cue order.
- [x] Enrich Sync Narration titles from resolved ownership only.
- [x] Keep Guided Navigation on its current enrichment path.

## Task 4 — Complete anchored seeking on iOS

- [x] Port Android's lookup by assigned `tocHref` after exact cue lookup.
- [x] Match each candidate's text resource, including later resources in an overlay.
- [x] Preserve explicit-time priority and unknown-anchor fallback policy.
- [x] Keep fragmentless resource/progression behavior and combined-locator fields intact.
- [x] Preserve Android's cached resume locator after an unmapped seek; reproduce and fix
      the discovered `play(null)` failure through the integration test.

No target index or Dart contract change is required for the current fixture cases.
Parents containing only nested subsections remain an explicitly deferred limitation.

## Task 5 — Integration, validation and consumer documentation

- [x] Generate example fixtures through `bin/build_test_fixtures` using the current source
      repository, including the now-available #259 section-child fixture.
- [x] Extend the native ToC integration test to assert owner and same-resource seeking.
- [x] Exercise unknown-anchor no-rewind behavior through the native navigator path.
- [x] Run `bin/unit_tests ios` and `bin/unit_tests android`.
- [x] Run `ktlint --format` on each edited Kotlin file.
- [x] Run `flutter build ios --no-codesign` from `flutter_readium/example`.
- [x] Run `./gradlew :flutter_readium:compileDebugKotlin` from the example Android directory.
- [x] For changed integration-test Dart: run `bin/format` and `bin/analyze`.
- [x] Run `integration_test/groups/timebased_playback_test.dart` on available iOS and Android
      devices. Record unavailable device checks honestly; model tests are not playback evidence.
- [x] Update `flutter_readium/CHANGELOG.md` under Unreleased and check the final diff.

Run long-lived Flutter sessions asynchronously; follow [the testing guide](../agent-testing.md).
No toolkit upgrades, web changes, broad native navigator refactors or unrelated audio-reading-order
changes are included. TestResources and the dirty sibling fixture checkout remain unchanged.

## Historical validation record

The following counts record the earlier validation pass; they are historical and superseded
by the latest coverage record linked above. Baseline was upstream main `c3b2225`, with iOS initially seeded from #273 `ae6b702` to
exercise its inheritance behavior. Fixture generation used `readium-test-resources`
`fd0c3d6d`; the existing TestResources cross-file shape was also captured in native tests.

| Check | Result |
| --- | --- |
| Before fix: iOS app-hosted native regressions | Six failures, including reset, cross-file ownership and structural seek |
| Before fix: Android native regressions | Four ownership failures after enabling real URI handling |
| `bin/unit_tests ios` | 60 passed, zero failed |
| `bin/unit_tests android` | 80 passed, one existing skip, zero failures/errors |
| `ktlint --format` on all five edited Kotlin files | Passed; corrected an existing private constant naming violation without changing its stored key |
| `bin/format` and `bin/analyze` | Passed after formatting the edited integration test |
| `flutter build ios --no-codesign` | Passed; unsigned device build |
| `./gradlew :flutter_readium:compileDebugKotlin` | Passed after the Android caller fix |
| Focused native ToC example test, iPhone 18 Pro / iOS 27 | Passed |
| Same test, pixel9 API 36 emulator | Passed |
| Live iOS example app and Dart-tool hot reload | Passed |

The focused command, run from the example directory on each device, was:

```sh
flutter test integration_test/groups/timebased_playback_test.dart -d <device-id> \
  --plain-name 'native ToC section navigates to its first narrated child'
```

It checks inherited `tocHref`, first narrated child, a later timed seek, resume near ten
seconds after an unknown anchor, and a known same-file section seek back to its first cue.
The initial Android test incorrectly assumed a rejected seek returns false through the
public channel. The corrected behavioral check exposed the cached-locator resume bug;
it failed before that caller fix and passed afterward.

Robolectric 4.17 is test-only: plain JVM Android stubs cannot execute Readium's URI handling.
No runtime dependency was added. Bootstrap changes to the example lockfile and SPM resolved
file were removed from the final diff. Generated fixtures remain ignored and source repos
were not modified.

The whole timebased integration group, web, physical devices, direct taps in native content,
and multi-audio cross-file playback were not exercised. No claim is made that the existing
iOS multi-audio reading-order limitation or deferred parent-only navigation is fixed.

## Contributor handoff

Once this work is reviewable, ask the user before pushing. Link the ADR and implementation
PR to the contributor only with explicit authorization. Explain the retained parent fix,
resource-boundary correction, and measured owner/seek behavior; separate synthetic edge-case
coverage from cases seen in the fixture corpus.
