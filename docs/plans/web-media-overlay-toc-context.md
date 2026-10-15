# Web Sync Narration ToC ownership and navigation

**Decision:** [ADR 0001](../adr/0001-native-media-overlay-toc-ownership.md).
**Base:** `c23c3abc`; native dependency [PR #274](https://github.com/Notalib/flutter_readium/pull/274).
**Status:** Implemented; see the [latest ADR 0001 regression record](media-overlay-adr-regressions.md). Both shared focused cases now pass on Chrome with autoplay enabled and range-capable fixture serving.

## Scope and tasks

- [x] Add failing public-parser regressions before production edits. Three ownership
  cases failed: parent/nested restoration, own audio with children, and resource boundaries.
  Four lookup cases also failed; flat-heading and no-ToC behavior already passed.
- [x] Assign owners inside each recursive Sync Narration list, emit own cue before
  children, restore caller state and attach titles only to assigned owners.
- [x] Opt Sync callers into explicit-time, exact-anchor, assigned-owner and gated
  resource fallback lookup. Match text or audio resources and preserve requested offsets.
- [x] Derive active lookup policy from the installed audio publication for `goTo`/`play`.
  Preserve Guided Navigation priority/defaults and existing bridge serialization.
- [x] Add the generated section fixture to web availability/manifest maps; run the
  existing shared integration case for web with all ownership, time and resume assertions.
- [x] Complete Jest suite (23 suites / 350 tests), `bin/typecheck` and `bin/update_web_example`.
- [x] `bin/format` and `bin/analyze`: no formatting changes or analysis issues after
  temporary browser target removal.
- [x] ChromeDriver example test: first section cue/owner, later `t=10` cue, unknown
  same-file anchor followed by `play(null)` without rewind, and known section seek back.

- [x] Uncued ToC targets (ADR 0001 amendment, local newspapers): `mediaoverlay/uncuedTocTargets.ts` fills ToC owners by document order per resource and anchors seeks to the first cue inside an uncued element. Jest: `uncuedTocTargets.test.ts`.

## Limits

No target index for parents whose cues all belong to nested subsections. No new audio-less
flat-heading activation, cross-file anchored-parent inheritance, URL canonicalization,
DOM-derived scope beyond uncued ToC targets, or Guided structural inheritance. iOS multi-audio playback remains
outside this change. Web fragmentless/progression mapping keeps its existing behavior;
this change does not promise identical native/web progression calculations. Browser
coverage exercises API-driven navigation, not physical content-tap dispatch.

## Initial implementation validation

The record below predates the coverage follow-up linked above.

ChromeDriver passed warm-up plus the shared ToC case, then passed again against the
latest bundle and diagnostic-enhanced shared test: first cue/owner, later `t=10`
cue, unknown-anchor resume at >=9 seconds, and known same-file section seek back.
The parent used a temporary focused wrapper extracting the shared test verbatim; the
tracked aggregator and runner remain unchanged. The command used the repository driver:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=_codex_web_toc_check.dart -d web-server \
  --browser-name=chrome --driver-port=4446 \
  --web-browser-flag=--autoplay-policy=no-user-gesture-required
```

To rerun the committed suite, use `integration_test/plugin_integration_test.dart`
as the target instead of the removed temporary wrapper. That runs the full aggregator;
this change was validated with the focused case only.

The initial run without the autoplay flag passed cue mapping but timed out waiting for
playing state. Automated playback needs this allowance; manual user-gesture playback
and physical content taps were not exercised. The full integration aggregator was not run.

Native production files are unchanged; native builds and simulator runs are outside this web-only gate scope.
