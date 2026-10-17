# Native media-overlay ToC context implementation tasks

**Decision:** [ADR 0001](../adr/0001-media-overlay-toc-ownership.md).
**Branch:** `fix/media-overlay-toc-context`, from main `c3b2225`.
> **Implemented locally.** Publication requires user confirmation; no push or PR has occurred.

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

## Task 6 — Uncued ToC targets (local newspapers)

ADR 0001 amendment, 2026-10-16. Lookup time only; parser ownership is unchanged.

- [x] Build a synthetic fixture with the structure of a real local newspaper ([readium-test-resources#4](https://github.com/Notalib/readium-test-resources/pull/4)).
- [x] Add an XHTML element id tree (`XhtmlIdTree`) on iOS and Android, cached per resource.
- [x] Current ToC entry: map ToC fragments that are not content ids to their first content descendant before the document-order lookup.
- [x] Seek: after exact cue and assigned-`tocHref` lookup fail, anchor the locator to the first cue inside its element.
- [x] Unit tests for the id tree in Swift (`TocAnchorTests.swift`) and Kotlin (`XhtmlIdTreeTest.kt`).
- [ ] Integration test with the synthetic newspaper, after readium-test-resources#4 merges.
- [ ] Web parity in [PR #276](https://github.com/Notalib/flutter_readium/pull/276).

## Validation record

Baseline was upstream main `c3b2225`, with iOS initially seeded from #273 `ae6b702` to
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

## Original fixture evidence and review follow-up


A Table of Contents (ToC) target can be an audio-less section containing narrated
children. [PR #259](https://github.com/Notalib/flutter_readium/pull/259) added inheritance
and structural seeking on Android. [PR #273](https://github.com/Notalib/flutter_readium/pull/273)
adds inheritance on iOS, but not structural seeking. Its reviewed head is `ae6b702`;
this implementation starts from main `c3b2225`.

The fixture inspection covered 38 Sync Narration documents and 330 cues in seven WebPubs:
`TestResources` at `05abfbeb`, and current `readium-test-resources` at `fd0c3d6d`.

- The current `38533_overlay_preview-toc-section-child` fixture targets an XHTML section
  without audio. Its narrated heading and paragraphs must inherit that section.
- Ordinary previews target narrated headings followed by paragraphs inside a wrapper.
  Continuing the heading's ToC reference is existing behavior worth preserving.
- No sampled JSON combines a matching container with a different matching descendant
  heading. The parent-reset regression is reproducible with that synthetic combination:
  #273 and Android give the heading its subsection, then the next paragraph its ancestor.
- Five `TestResources/WebPub/ValidWithAudio` documents contain the next file's first page
  cue under the previous file's container. Both files have their own fragmentless ToC entry.
  Unrestricted inheritance assigns that boundary cue to the previous chapter.
- All sampled JSON has one wrapper level followed by cues. It does not establish semantics
  for deeper subsection boundaries, headings without audio, or parents owning no cues.

### Uncued ToC targets (local newspapers)

Nota local newspapers point ToC entries at a `<section>` or `<aside>` that is neither a cue nor a Sync Narration container. The narration lists only the paragraphs inside it, with no `seq` for the section. EPUB 3.3 §9.3.2.1 makes that `seq` optional, so the content is valid, but parser ownership cannot see the section. The playing locator then got no `tocHref`, skip-to-next-ToC fell back to the reading order ("At the last chapter" in single-file issues), and a seek to such an entry in the playing file failed under #139.

The synthetic fixture `synthetic_local_newspaper` ([readium-test-resources#4](https://github.com/Notalib/readium-test-resources/pull/4)) copies the structure of a real issue: 19 resources, 305 cues, 21 ToC entries. 18 entries target a cue-less `<section>`, one targets an `<aside>`, and one `h2` entry is itself a cue.

The cross-file sequence also exists in the source SMIL. Narration grouping therefore
cannot be assumed to mean strict DOM containment. These are fixture observations, not
claims that upstream Readium specifies the ownership policy below.


The original native implementation began at `c3b2225`, with #273 reviewed at `ae6b702`. Reviewed native head `e8a324f6` was merged with main `43ac49ee` before this follow-up. These are historical evidence points, not part of the ADR contract.

An integration run also exposed an Android caller bug: a rejected seek replaced the cached resume locator. Preserve it when no audio mapping exists, and assert playback position rather than the public navigation acknowledgment.

The October 16 review identified prelude ownership, cue-less heading navigation, equivalent owner-lookup tests, actual locator rewriting, asynchronous web caller coverage, and cross-resource skip coverage. The accepted policies are recorded in ADR 0001. Fixture updates are pending user review in the source repository; do not claim CI coverage until that revision is published.

### Follow-up validation (2026-10-16)

- iOS example device build without codesigning: passed. Native XCTest result bundle: 75 passed, no failures or skips.
- Android example compilation: passed. Native JUnit/Robolectric suite: 98 passed, one existing ignored test, no failures.
- Equivalent tests now cover prelude file-only/unowned policy and actual locator rewriting for forward, unknown, after-last, explicit-time, and metadata-preservation cases.
- Initial locators use the same XHTML resolution before audio navigator initialization. The shared one-minute fixture integration test is developed in PR #276; simulator/browser qualification and fixture publication are pending.
- The Xcode build removed the tracked generated SwiftPM `Package.resolved`; it is deliberately excluded from the scoped implementation commit.

- Android delayed-enrichment regression: passed. The existing serialized emission step is now tested with a blocked first lookup and an already-owned second cue; delivery stays in order. Full native suite: 99 passed, one existing ignored test.
- Shared compact-fixture integration on iPhone 18 Pro / iOS 27 simulator: passed (warm-up, committed newspaper case, result reporter; approximately 30 seconds test execution). This run used the local uncommitted fixture revision and includes initial forward seeking, prelude/deeper owner rules, same-file no-rewind/resume, and cross-resource next/previous.
