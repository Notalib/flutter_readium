# Cross-platform Audio Stall Watchdog Plan

## Goal

Make audiobook stall recovery use the same simple definition on iOS, Android,
and web:

> While playback is requested, recover only when neither the current resource
> nor its playback position has changed meaningfully for the configured stall
> timeout.

Reported player state (`playing`, `paused`, `loading`) is not sufficient evidence
on its own. Native players can continue reporting `playing`, or move to
`paused`, after streamed data runs out. Resource identity plus media position is
the cross-platform liveness signal.

## Current evidence

- The iOS user report clusters near the default 20-second timeout and describes
  a brief stutter or replay of a few seconds. Rebuilding the navigator from its
  last emitted locator explains that symptom.
- The iOS implementation now checks progress instead of trusting Readium's
  state, and the synthetic HTTP test proves that a stream which starts and then
  stops delivering bytes can trigger recovery.
- The existing track-change regression passes on iOS but fails on the Android
  emulator with a 3-second test timeout. Android logs:

  ```text
  ::startStallWatchdog - offset hasn't advanced in 3.0s, synthesizing retryable error
  ```

  Android is therefore affected by an equivalent false-positive bug in the
  controlled test. We still do not have an Android field report showing the
  production 20-second symptom.
- Web already rearms a timer when the offset moves forward, but it does not use
  resource identity and does not treat a backward seek as activity. Its current
  comments promise stronger parity than the implementations provide.

## Why Android fails

Android remembers only the previous offset. If one track ends around 9 seconds
and the next begins at 0, the new track is considered frozen until it exceeds 9
seconds. A short configured timeout can therefore fire during healthy playback.
The same comparison can mishandle a backward seek within one track.

iOS already includes resource index in its current check, but its fixed snapshot
windows can detect a real stall almost two timeouts after the last movement. The
web implementation has the same missing resource/seek semantics as Android.

## Shared behavioral contract

Each implementation keeps these four values locally:

- whether playback is requested;
- the last observed resource identity;
- the last observed playback position;
- a monotonic timestamp for the last meaningful activity.

Meaningful activity is any of:

- the resource identity changes;
- the position changes by more than 100 ms in either direction;
- playback is explicitly resumed, which starts a fresh observation window.

The watchdog fires only when playback remains requested and the monotonic time
since meaningful activity reaches `stallTimeoutSeconds`. It is disabled for an
explicit pause, end, active recovery, terminal failure, or disposal.

The 100 ms tolerance prevents timestamp noise from keeping a dead stream alive.
Using absolute position change deliberately counts both playback advancement and
seeks as activity. After a navigator rebuild, recovery verification must remain
stricter: it succeeds only after forward playback, not merely any position
change.

Player state and playback rate may be logged as diagnostics, but neither gates
stall detection. A timer must still be able to fire when player callbacks stop
entirely.

## Architecture decision

Do not add a Dart watchdog or a shared cross-language state machine. Timers,
player observations, and lifecycle ownership are already platform-local. Keep
the implementations small and synchronize them through this contract and the
same test cases.

Scheduling can remain idiomatic per platform. A watchdog may fire up to one poll
interval after the deadline, but progress must always move the deadline from the
time that progress was observed.

## Implementation tasks

### 1. Lock the contract down with pure tests

- [ ] Add the same focused state-transition cases to Swift, Kotlin, and
  TypeScript tests before changing production behavior.
- [ ] Keep the helper surface minimal: an observation of resource plus position,
  and a decision to reset, continue, stop, or declare a stall.
- [ ] Keep post-rebuild forward-progress verification separate from the stall
  liveness helper.

Required cases:

1. First observation establishes a fresh deadline.
2. Frozen resource and position reach the timeout and declare one stall.
3. Forward position movement resets the deadline.
4. A backward seek resets the deadline.
5. A resource change with its normal offset reset resets the deadline.
6. Explicit pause disables the deadline.
7. Resume starts a complete new timeout window.
8. End, recovery, terminal failure, and disposal disable the watchdog.
9. A check before the deadline does not fire; a check at or after it does.
10. Rebuild verification still requires forward playback.

### 2. Simplify iOS around a rolling deadline

- [ ] Replace the fixed snapshot-window behavior in
  `FlutterAudioNavigator.swift` with a last-activity deadline.
- [ ] Use a monotonic clock (`ContinuousClock` if supported by the pinned build
  target, otherwise system uptime).
- [ ] Observe resource index and time while `_playbackIntent` is true.
- [ ] On meaningful activity, update the observation and deadline. At timer
  wake-up, sleep until a moved deadline or recover if it has expired.
- [ ] Preserve cancellation on pause, end, recovery, failure, and disposal.

This should revise the current iOS progress-based watchdog, not introduce a
second watchdog beside it.

### 3. Correct Android resource and seek tracking

- [ ] Extend the Android observation from offset alone to resource index plus
  offset.
- [ ] Count an absolute position delta greater than 100 ms as activity.
- [ ] Replace `System.currentTimeMillis()` deadlines with
  `SystemClock.elapsedRealtime()`.
- [ ] Keep the existing coroutine poll loop and `playWhenReady` intent signal;
  do not replace them unless tests expose a concrete lifecycle problem.
- [ ] Ensure only one recovery is synthesized for an expired observation.

### 4. Align web semantics

- [ ] Track resource href plus offset when deciding whether to rearm the timer.
- [ ] Count meaningful backward and forward position changes.
- [ ] Track requested playback explicitly if `nav.isPlaying` can become false
  while buffering; validate this with a focused player test before changing it.
- [ ] Keep browser `stalled` events as immediate UI information only. The
  configured no-progress timeout remains the recovery threshold.

Although the reported issue is native, the recovery policy is public and shared
across all three platforms. Leaving web with different semantics would preserve
the same cross-track defect there.

### 5. Resolve interruption and suppression semantics

- [ ] Inspect the pinned Swift and Kotlin toolkit behavior for audio-session or
  audio-focus interruptions.
- [ ] If a platform exposes an unambiguous external-suppression signal, suspend
  the watchdog during that suppression without changing playback intent.
- [ ] Otherwise, add temporary diagnostics and perform a device test before
  introducing another heuristic. Do not infer interruptions from `paused` or
  rate zero alone.

This is the only open behavior question. It does not block fixing the confirmed
track-change false positive, but it must be resolved before claiming the
watchdog is complete.

## Integration regression matrix

- [ ] **Real stall:** a synthetic loopback HTTP response supplies enough valid
  audio to begin playback, then stops sending bytes. Expect exactly one
  `AudioStreamRetry` after the short configured timeout on iOS and Android.
- [ ] **Track change:** start near the end of one resource and continue into the
  next. Playback must advance beyond the timeout with no retry on iOS and
  Android. This is currently green on iOS and red on Android.
- [ ] **Explicit pause:** remain paused longer than the timeout. Expect no retry,
  then a fresh full window after resume.
- [ ] **Backward seek:** seek backward and continue healthy playback for longer
  than the timeout. Expect no retry.
- [ ] **Continuous playback:** play for at least two timeouts without a retry.
- [ ] Add web fake-timer coverage for the same liveness transitions. Add a web
  streaming integration case only if the existing browser harness can
  deterministically hold a response open.

The synthetic server belongs in integration tests: it exercises HTTP delivery,
the native player, Readium callbacks, the plugin watchdog, and the Dart event
channel together. Pure watchdog decisions remain unit tests.

## Verification gates

- [ ] Run the focused Swift XCTest watchdog cases.
- [ ] Run Android unit tests and
  `:flutter_readium:compileDebugKotlin` from the example Android project.
- [ ] Run web unit tests and the web package build if TypeScript changes.
- [ ] Run the real-stall and track-change integration tests on both an iOS
  simulator and Android emulator.
- [ ] Run `bin/format` and `bin/analyze`.
- [ ] Run `flutter build ios --no-codesign` from `flutter_readium/example`.
- [ ] Manually check interruption behavior on physical iOS and Android devices
  if simulator/emulator controls cannot reproduce audio focus changes reliably.

## Acceptance criteria

- A healthy resource transition or backward seek cannot trigger recovery.
- A stream whose media time genuinely stops reaches one recovery attempt within
  the configured timeout plus scheduler tolerance.
- Explicit pause, end, recovery, failure, and disposal cannot trigger the
  watchdog.
- iOS, Android, and web implement the same liveness definition even where their
  scheduling mechanisms differ.
- The existing Android track-change regression is green and no longer logs the
  watchdog warning.
- The positive synthetic-stream test is green on both native platforms.
- Changelog platform scope is updated only for platforms whose fix passes this
  matrix.

## Commit and delivery sequence

1. `test(audio): define stall watchdog regressions`
2. `fix(ios): track rolling audio playback progress`
3. `fix(android): reset audio stalls across navigation`
4. `fix(web): align audio stall liveness`
5. `docs(audio): update stall recovery behavior`

Keep these as additive commits on the existing fork branch; do not force-push or
open a pull request without explicit approval.
