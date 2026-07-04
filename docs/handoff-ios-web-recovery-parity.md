# Handoff — iOS/Web audio-recovery parity, then Unified Error Surface (Option A)

Branch: `feat/ios-audio-error-recovery` (nothing pushed). Android audio-stream recovery is
complete, hardened, and manually validated by the user against Link Conditioner. iOS and
Web have the *feature* but not the *hardening* fixes. Then land the unified error surface.

## 1. Goal of next session

Bring **iOS and Web** audio-stream recovery to parity with the hardened **Android**
implementation, then execute the **Option A** plan in
[unified-error-surface-draft.md](unified-error-surface-draft.md). Android is the reference —
do not re-derive; mirror it.

## 2. State of play

**Done (Android, validated):** stall watchdog, bounded recovery rebuild, bounded initial
navigator create, dispose latch (no resume after close), per-attempt terminal-code
specificity, and `AudioRecoveryPolicy.connectionTimeoutSeconds` (default 10s). Reference
commits `bdbf6e81`, `6b3993a2`, `964adc77`, `8f1f3b8d`; reference files
`flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/navigators/AudiobookNavigator.kt`
(watchdog, `offsetAdvanced`, bounded `rebuildNavigator`/`initNavigator`, `disposed` latch,
`startRecovery` `terminalCode`) and `.../navigators/AudioStreamErrorPolicy.kt`.

**Done (all platforms):** typed `ReadiumErrorCode`, structured `ReadiumError.details`,
`AudioRecoveryPolicy` config + method channel. iOS/web policy structs already carry
`connectionTimeoutSeconds` (parity field added in `964adc77`) but their recovery loops
**do not consume it yet**.

**Not done (iOS + Web), mirror Android:**
1. Watchdog: currently resets its stall deadline while state != Ready — but a stall sits in
   Buffering, so it never fires. Fix = only reset on genuinely-not-playing (paused/ended);
   Buffering-with-play-intent + frozen offset must count. (Android fix: `bdbf6e81`.)
2. Bound the recovery rebuild **and** the initial navigator create with
   `connectionTimeoutSeconds`, else sustained/total loss hangs the loop / open. (`6b3993a2`,
   `8f1f3b8d`.) iOS `startRecovery` is in `FlutterAudioNavigator.swift`
   (`handleResourceReadError` is the only current trigger — no stall observation); web in
   `web/src/navigators/FlutterAudioNavigator.ts` + `AudioStreamErrorPolicy.ts`.
3. Carry the classified error code through to terminal failure (not generic
   `AudioStreamFailed`).
4. Ensure dispose/close cancels recovery and can't resume after close (Android `disposed`).

**Still-open Android bug (carry, don't lose):** under 100% loss *mid-playback*, it retries
**once** then stalls until the user presses pause, which revives it. Root cause not yet
confirmed — needs a log slice (first `AudioStreamRetry` → pause, ~20–40s). Three candidates
documented in the session; leading one: the playback flow's
`distinctUntilChangedBy { "state|playWhenReady" }` dedups a repeat `State.Failure`, and pause
flips `playWhenReady` (key changes) so the suppressed failure finally emits. Fix only after
the log confirms which.

## 3. Open decisions

- **Dual-signal at init timeout.** Android's offline-open timeout both emits a terminal error
  event *and* throws (`PlatformException`); the example now catches the throw (`77275c3a`).
  Reconcile under Option A: method-call failures → thrown/`PlatformException`; ambient
  failures → error event. Decide whether init-timeout is method-call-only (drop the event) or
  keep both. Lean: method-call-only, per the two-paths model.
- **Option A ⚖️ items** (4) in [unified-error-surface-draft.md](unified-error-surface-draft.md):
  adopt A; deprecate `OpeningReadiumExceptionType` (alias-one-release vs hard-cut); drop
  `stackTrace` from the wire; timing of steps 3–4. User has pre-approved **Option A**.
- **connectionTimeoutSeconds default** is 10s; confirmed by user. Stall watchdog default 20s.

## 4. Skills to use

- `superpowers:systematic-debugging` — for the still-open "retry once, pause revives"
  Android bug: get the log slice, confirm the cause, then fix. Do not patch before evidence.
- `superpowers:verification-before-completion` — run each platform's build/verify (§5) and
  quote the output before claiming any platform done; native network behaviour is
  user-validated, so say so explicitly.
- Code research: use `tokensave_*` (this branch is tracked); mirror the Android reference
  files named in §2 rather than re-deriving the design.

## 5. Artifacts

- Plans: [audio-recovery-policy-config-plan.md](audio-recovery-policy-config-plan.md),
  [unified-error-surface-draft.md](unified-error-surface-draft.md),
  [upstream-audio-error-surfacing-plan.md](upstream-audio-error-surfacing-plan.md) (parked).
- Vocabulary + policy fields: [api-reference/error-codes.md](api-reference/error-codes.md).
- Consumer guide: [guides/audio-network-recovery.md](guides/audio-network-recovery.md).
- Assessment: [error-mapping-assessment.md](error-mapping-assessment.md).
- Repo rules: `CLAUDE.md` (per-platform build/verify, ktlint, bridge serialization, changelog
  scope). Verify each platform before done: iOS `flutter build ios --no-codesign`, Android
  `:flutter_readium:compileDebugKotlin` + ktlint, web `bin/typecheck` + `bin/update_web_example`,
  Dart `bin/analyze` + tests. Manual network validation is delegated to the user.
