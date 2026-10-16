# ADR 0001 regression and validation record

This page records the latest focused regression evidence for [ADR 0001](../adr/0001-media-overlay-toc-ownership.md).
It complements the implementation details in the [native checklist](native-media-overlay-toc-context.md)
and [web checklist](web-media-overlay-toc-context.md). Counts below are from the current worktree
validation on 2026-10-14 unless explicitly dated below. The October 16 follow-up supersedes those counts.


## Review follow-up, 2026-10-16

Fixture source: [`fc12500`](https://github.com/Notalib/readium-test-resources/commit/fc12500bd36fbfe68bab15e24067c53a576c3e62). The synthetic newspaper is now three resources, six ten-second cues, and one minute of generated tones. It retains an unowned prelude, a cue-less heading before narrated content, a section/deeper-heading shared start, an uncued section and aside, and a following resource. Manifest anchors, audio durations, and archive construction were checked locally.

The web seek-instability regression failed before the fix: the same section selected cue 1 before `fillOwners()` and cue 0 afterward. It now selects cue 1 both times. Prelude ownership uses a file-only entry or remains unowned on every platform. Navigation to a known cue-less element selects the first cue at or after it, separately from ownership; unknown and after-last targets retain the ADR's fallback/no-match rules.

| Layer | Follow-up evidence |
| --- | --- |
| Swift units | 75 passed; equivalent owner-index policy and actual locator rewrite checks |
| Kotlin units | 99 passed, one existing ignored test; includes slow enrichment followed by an already-owned cue |
| Web units | 25 suites / 396 passed. Real DOMParser XHTML/HTML recovery, prelude policy, before/after-fill seek stability, metadata/time preservation, initial locator, goTo/play/audioEnable callers, terminal recovery, stale-session rejection, and first event while owner loading is pending |
| iOS reader integration | Expanded committed newspaper case passed on iPhone 18 Pro / iOS 27 simulator |
| Chrome reader integration | Expanded committed newspaper case passed on Chrome 155 with autoplay and range-capable local fixture serving |
| Android audio integration | Same case passed on API 36 with reader mounting omitted in a temporary diagnostic runner |
| Android full reader integration | Blocked during warm-up by the upstream 3.4.0 WebView crash below; narration case never started |

The shared case checks initial seeking from the empty heading, prelude ownership, the deeper heading winning a shared cue, identical seeks after enrichment, same-file unknown-anchor resume without rewind, section/aside seeking in both directions, owner continuation at the next cue, and next/previous ToC navigation across a resource boundary. It waits for cue, owner, and offset to agree. After paused seeking it explicitly resumes playback, so a missing duplicate paused event cannot masquerade as a failed seek. Timing assertions allow the full ten-second cue window; exact lookup offsets are covered in units.

Focused runs use a temporary runner containing the committed newspaper test body verbatim, plus the normal warm-up/result reporter. The separate Android diagnostic omits reader mounting and warm-up only; it does not replace or weaken the committed full-reader test. Full integration aggregators and physical-device/content-tap checks were not rerun for this follow-up. The historical full-suite results below do not qualify this head.

### Android reader blocker

The API 36 app crashes in warm-up before any narration request:

```text
java.lang.NullPointerException: getResponseHeaders(...) must not be null
  at org.readium.r2.navigator.epub.WebViewServer.allowCors(WebViewServer.kt:262)
  at org.readium.r2.navigator.epub.WebViewServer.shouldInterceptRequest(WebViewServer.kt:116)
```

The pinned [Readium 3.4.0 source](https://github.com/readium/kotlin-toolkit/blob/3.4.0/readium/navigator/src/main/java/org/readium/r2/navigator/epub/WebViewServer.kt#L262) adds a CORS header to `responseHeaders` without handling null for asset responses. This needs an upstream null-safe header merge and a published toolkit fix; no library artifact was decompiled or patched locally. Audio-only qualification establishes the ADR's navigation behavior but cannot substitute for a successful reader run.

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
full aggregators subsequently passed in hosted CI; local native integration validation
covered the two ADR-focused cases. Existing platform-gated cases retain their normal
exclusions.

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
- One new synthetic fixture, `adr-sync-narration-ownership`, was merged in
  [readium-test-resources #3](https://github.com/Notalib/readium-test-resources/pull/3)
  as `8173e3d`; its source matches the tested `4a23591` unchanged. It covers the missing
  integration shapes using two text files and one 22-second audio track. Parser-only
  edge cases use small inline inputs; no additional packaged fixtures are needed.
  Dependent plugin CI can now fetch the fixture from source `main`.

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
The first hosted #276 run passed quality, Android/web unit tests and all three full
integration aggregators. Its iOS unit job hit the 20-minute job timeout without reporting
an assertion failure. A [targeted rerun](https://github.com/Notalib/flutter_readium/actions/runs/38573569292/job/116146080654)
passed 69 tests in 18 minutes 55 seconds overall on 2026-10-15. The unit workflow now has
a 30-minute job budget, a 20-minute test-step limit, and retained Xcode log/result-bundle
artifacts. Its new command also passed all 69 tests locally on iOS 26.5 and produced a
valid result bundle. The [updated hosted run](https://github.com/Notalib/flutter_readium/actions/runs/38652287144/job/116153745914)
passed all 69 tests in 14 minutes overall on the standard runner.

### iOS unit-test performance follow-up

The unit job uses `macos-26-xlarge`, matching integration, and keeps its own simulator/job
because XCTest previously shut down a simulator shared with integration tests. The pinned
Flutter SDK is cached through the existing setup action. CocoaPods has a dedicated unit-job
cache keyed by architecture, Podfile and lockfile.

A dedicated `ReadiumUnitTests` DerivedData directory caches build outputs separately from
integration. Keys include the actual Xcode version/build, runner architecture, Flutter pin,
CocoaPods/SwiftPM manifests and locks, and commit. Compatible source changes can restore a
previous build; toolchain/dependency changes start cold. Xcode compilation caching and its
diagnostic remarks are enabled, with the compiler cache stored inside this directory.
Plain DerivedData restoration alone rebuilt every Swift source on an exact cache hit, so a
successful GitHub cache restore is not treated as proof of compiler reuse.

Hosted evidence on 2026-10-15, with all 69 tests passing in each run:

| Configuration | Total job time | Evidence |
| --- | --- | --- |
| Standard runner | 18m55s / 14m00s | [Retry](https://github.com/Notalib/flutter_readium/actions/runs/38573569292/job/116146080654), [diagnostic run](https://github.com/Notalib/flutter_readium/actions/runs/38652287144/job/116153745914) |
| Larger runner, plain DerivedData cold / warm | 6m22s / 6m14s | [Cold](https://github.com/Notalib/flutter_readium/actions/runs/38654358067/job/116160517462), [warm](https://github.com/Notalib/flutter_readium/actions/runs/38654358067/job/116164766289); both logged 1,293 Swift compile entries |
| Larger runner, compilation cache cold | 7m40s | [Cold](https://github.com/Notalib/flutter_readium/actions/runs/38656617918/job/116167834492); compiler cache populated |
| Larger runner, compilation cache restored on a fresh runner | 10m11s | [Reuse](https://github.com/Notalib/flutter_readium/actions/runs/38657468635/job/116170764850); 269 compiler-cache replay hits |

Compiler reuse is confirmed, but these samples do not establish a total-time improvement
from caching alone. The last run spent 2m24s downloading/installing Flutter, roughly 30s
restoring the build cache and 33s saving it, and 70s launching/testing/reporting. Its build
window was approximately 3m13s versus 3m22s for the cache-populating run. Enabling the setup
action's SDK cache addresses the repeated multi-gigabyte SDK download. The [final SDK-cache
workflow](https://github.com/Notalib/flutter_readium/actions/runs/38699183359/job/116302993971)
passed all 69 tests in 7m12s on 2026-10-15, restored the CocoaPods and Xcode caches, logged
41 compiler-cache replays and saved the Flutter SDK cache. This validates the final workflow
and cache population; a subsequent fully warm SDK-cache timing has not been measured.
Workflow lint, YAML parsing and embedded shell syntax checks pass.

The reuse run's iOS integration, API 36 Android integration, web integration, quality and
Android/web units passed. Android API 24 hit the 30-minute job limit while installing the
APK, before any tests ran; this cancelled the enclosing workflow despite the successful
iOS unit job. The [final workflow run](https://github.com/Notalib/flutter_readium/actions/runs/38699183359)
subsequently passed all three full integration aggregators, including both Android API 24
and API 36 jobs. Quality and Android/web unit checks also passed on the same head. No
Android workflow or production code changed in this optimization.

The ownership and locator tests could move into a smaller iOS logic-test target using
`ReadiumShared`, the overlay model, media-time helper and relevant locator extensions.
The model itself does not import Flutter. However, the current tests import the complete
`flutter_readium` module; its package includes Flutter, ReadiumNavigator and the remaining
plugin. Locator helpers also share a file with navigator/publication extensions. A useful
split would compile these same production sources without duplicating their logic and
keep bridge/playback tests in the app-hosted suite.

An isolated local test on iOS 26.5 cleared `TEST_HOST` and `BUNDLE_LOADER` and selected
`FlutterMediaOverlayTests` / `FlutterMediaOverlayTocTests`. Compilation succeeded, but
XCTest could not load the bundle because `CryptoSwift.framework` was unavailable outside
the app's framework embedding. No selected tests executed. The current scheme also still
built Runner, so changing these settings alone does not remove the expensive build.
A separate target and dependency separation are follow-up work; the CI suite retains all
69 app-hosted tests. Separating the pure subset would speed focused checks, but the
remaining app-hosted tests would still build Runner in full CI; the split alone does not
remove that job's build from the critical path. No Swift sources or test-target settings
changed in this optimization.

## Limits and unrun checks

The integration tests do not cover every parser edge. Direct content taps/manual gesture
dispatch, physical devices and multi-audio playback remain unrun. Existing malformed/open-ended native timing differences are preserved outside
this ADR's shared valid-cue contract.
