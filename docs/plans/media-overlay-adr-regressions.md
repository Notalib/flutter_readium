# ADR 0001 regression and validation record

This page records the latest focused regression evidence for [ADR 0001](../adr/0001-native-media-overlay-toc-ownership.md).
It complements the implementation details in the [native checklist](native-media-overlay-toc-context.md)
and [web checklist](web-media-overlay-toc-context.md). Counts below are from the current worktree
validation on 2026-10-14 unless explicitly marked historical.

## Coverage matrix

| Layer | Coverage | Latest result |
| --- | --- | --- |
| Swift unit tests | Ownership, recursion, resource boundaries and lookup | 69 passed |
| Kotlin unit tests | Ownership, recursion, resource boundaries and lookup | 93 total: 92 passed, 1 existing skip |
| Web Jest | Parser ownership, lookup and playback state | 23 suites / 370 tests, all passed |
| iOS focused integration | Two focused ToC cases on iPhone 18 Pro / iOS 27 | Passed |
| Android focused integration | Same two focused ToC cases on API 36 emulator | Passed |
| Web ChromeDriver integration | Full web aggregator, Chrome 155; includes both ADR cases | 28 reported tests passed with autoplay enabled |

The same two integration cases run on all three platforms. They cover parent ownership,
known same-resource section seeks, timed cue ownership, unknown same-resource no-rewind,
unknown cross-resource fallback, nested-list restoration and repeated structural anchors.
The table below distinguishes end-to-end evidence from parser/lookup-only coverage.

| ADR case | Swift / Kotlin / web unit coverage | Shared integration coverage |
| --- | --- | --- |
| Audio-less parent and heading continuation | All three | Existing section-child fixture |
| Active heading A → wrapper/container B → A | All three, including both nested shapes | New ownership fixture |
| Resource boundary with file-only ToC owner | All three | New ownership fixture |
| Resource boundary without a known owner | All three | Unit only |
| Repeated structural ID in two resources | All three; no exact-cue match can hide the lookup | New fixture seeks second resource's first owned cue |
| Explicit time / exact cue / structural owner priority | All three | Timed and structural seeks; competing-anchor priority is unit only |
| Unknown same-resource anchor preserves resume | All three reject unmapped lookup; resume is verified in integration | Existing fixture, actual playback offset |
| Unknown cross-resource anchor permits fallback | All three | Existing fixture, actual first-cue offset |
| Shared audio boundary belongs to starting cue | Native range tests; Sync web helper, factory and Reader tests | Structural seek at the new fixture's exact boundary |
| Own audio plus children preserves traversal / caller state | All three | Unit only |
| Audio-less flat heading / no ToC / invalid narration | All three, preserving existing validation | Unit only |
| Time gap / after-last | All three | Unit only |
| Missing or reversed end | Existing Swift guards and web Sync policy tested; Android retains its existing behavior | Outside the shared ADR contract |
| Titles preserve resolved ownership | All three | `tocHref` is checked end to end; title window rules are unit only |
| Guided behavior stays unchanged | Existing native separation; explicit web default and dual-format tests | Existing Guided cases passed in full web aggregator |

The full web integration aggregator passed, including Guided playback followed by reader
mounting, image resource loading, decorations, fixed-layout and DiViNa navigation. Native
full aggregators were not run; their two ADR-focused cases passed. Existing platform-gated
cases retain their normal exclusions.

To reproduce the native focused runs from `flutter_readium/example`:

```sh
flutter test --no-pub integration_test/groups/timebased_playback_test.dart \
  -d <device-id> --name 'ToC section navigates|Sync Narration restores' --timeout=300s
```

Chrome first used a temporary example-root wrapper extracting these same two test bodies;
the wrapper was removed afterward. The final Chrome run used the committed
`integration_test/plugin_integration_test.dart` aggregator and repository driver.
`bin/integration_test_web` runs that same entry point. The host driver starts the fixture server
before navigating the browser, so no additional server process or dependency is needed.
A live Android example app hot reload also passed after the Dart changes.

## Regression evidence

- Mutation A restores the inherited parent after recursion instead of the caller's active
  heading; it makes two real web regression tests fail. Mutation B ignores the resource
  when matching structural owners; it makes one real regression test fail. Both mutations
  previously passed the old suite and are removed from the validated source.
- Five web boundary tests failed before the production fix. The Sync-only half-open interval
  correction resolves them while preserving Guided Navigation behavior.
- One new synthetic fixture, `adr-sync-narration-ownership`, is committed locally in
  `readium-test-resources` as `4a23591` on `test/sync-narration-adr`. It covers the missing
  integration shapes using two text files and one 22-second audio track. Parser-only
  edge cases use small inline inputs; no additional packaged fixtures are needed.
  Merge the source fixture before dependent plugin CI runs: the fetch action clones
  source `main` without pinning this new branch.

## Build and analysis gates

Passed: `bin/format`, `bin/analyze`, unsigned Swift iOS build, Kotlin compilation, ktlint,
web typecheck and web bundle generation. CI now has a separate reusable iOS unit-test job
with its own hosted macOS runner/simulator, and both local and CI web drive commands enable
Chrome autoplay. The host web integration driver also serves generated fixtures on
`127.0.0.1:8767` with byte ranges, HEAD and CORS; six real HTTP tests cover successful
ranges, invalid ranges, MIME/CORS, HEAD and path/symlink rejection. Flutter's dev server
ignores Range requests: a fresh Chrome audio element returned to zero after seeking the
new MP3 to 16 seconds, while the same bytes as a downloaded blob sought correctly.
Changing encoding or pausing before the seek did not solve it. With the fixture server,
the original playing-seek sequence and actual 16–18 second offset assertion pass.
Hosted CI has not been run for these edits.

## Limits and unrun checks

The integration tests do not cover every parser edge. Direct content taps/manual gesture
dispatch, physical devices, multi-audio playback, and the full native integration aggregators remain
unrun. Existing malformed/open-ended native timing differences are preserved outside
this ADR's shared valid-cue contract. The synthetic source fixture is not yet available
to hosted CI until its source change is merged.
