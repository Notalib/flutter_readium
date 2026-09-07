# Resource-loading Watchdog Re-scope

> **✅ Implemented (2026-09-07).** Supersedes the progress-based watchdog work
> in PR #223.

## Goal

Replace the continuously armed audiobook watchdog with a one-shot readiness
check:

> After playback starts or enters a new reading-order resource, require one
> real playback advance within `stallTimeoutSeconds`. Once it advances, stop
> watching that resource.

The timer may report a suspected loading stall. Rebuilding the navigator is a
separate opt-in policy switch, owned by the consuming application.

## Scope decision

The current watchdog can interpret any long pause in position as a network
failure, then rebuild from a slightly stale locator. The field report suggests
that this recovery path itself causes the audible stutter.

This re-scope deliberately prefers false negatives over destructive false
positives. It does not watch:

- a later freeze after the current resource has already played;
- a seek within the current resource, unless followed by `play()` or
  `resume()`; or
- buffering, paused, or stalled state changes during established playback.

Native playback and the existing authoritative error path remain responsible
for those cases. Cross-resource navigation is watched because it loads a new
resource.

## Contract

Keep the platform-local helper to three states:

- **idle:** no loading attempt is being timed;
- **armed:** waiting for the first forward progress after a load boundary;
- **reported:** the deadline expired and one warning/loading state was emitted.

Events have these effects:

- `play()` or `resume()` arms from the current resource and position.
- A resource identity change re-arms while playback is requested. The change
  itself is not successful progress.
- Forward movement greater than 100 ms in the armed resource returns to idle.
  It does not start a rolling deadline.
- Pause, authoritative end, interruption/suppression, recovery, terminal
  failure, and disposal return to idle.
- A resource change while paused is remembered but does not arm; a later resume
  does.
- Expiry logs once, emits `.loading` once with the current locator, and enters
  reported.
- Later native state events are not pinned or suppressed. Forward progress,
  pause, or a new load boundary clears reported.

Do not emit `AudioStreamRetry` unless recovery actually starts. Explicit
resource/player errors retain their current automatic classification and retry
behaviour.

## Recovery policy

Add one field to the public `AudioRecoveryPolicy` and its platform mirrors:

```dart
final bool recoverOnResourceLoadingTimeout; // default false
```

This is an application-facing runtime option. The consuming application may
derive it from its own configuration, but the plugin has no flavor or build-time
flag mechanism. When false, expiry only logs and emits `.loading`. When true,
expiry also enters the existing recovery loop.
`stallTimeoutSeconds` remains the reporting deadline; the other policy fields
continue to govern real recovery attempts.

Missing or invalid serialized values default to false. Extend `copyWith`,
equality, parsing, and serialization coverage. Do not add a second policy type,
callback interface, Dart timer, or shared cross-language state machine.

## Implementation sequence

1. Replace the rolling helper contract and add the application policy field; verify with focused Swift, Kotlin, TypeScript, and Dart unit tests.
2. Apply the one-shot lifecycle to iOS, including authoritative end cleanup; verify with Runner tests and iOS resource-loading integration cases.
3. Apply the same lifecycle to Android without adding a second intent model; verify with Kotlin tests and the same Android integration cases.
4. Apply the lifecycle to web and reconcile Media Session intent; verify with Jest, `bin/typecheck`, and `bin/update_web_example`.
5. Extend the existing loopback fixture and rewrite docs and changelogs around the new scope; verify the native matrix, builds, formatter, analyzer, and `git diff --check`.

## Implementation

### Tests and public policy

- Replace rolling-watchdog tests with the contract above on Swift, Kotlin, and
  TypeScript.
- Cover arm, one-shot expiry, forward-progress disarm, requested-resource
  re-arm, paused-resource no-op, lifecycle cancellation, and one report per
  attempt.
- Cover default reporting-only behavior and explicit recovery opt-in.
- Add the policy field across Dart, Swift, Kotlin, and TypeScript.

Verify: focused platform unit tests demonstrate that frozen time after the
first successful progress cannot expire until another load boundary occurs.

### iOS

- Arm from `play()` and `resume()`.
- Use `MediaPlaybackInfo.resourceIndex` to detect a new resource while
  `_playbackIntent` is true.
- Cancel on the first forward progress greater than 100 ms.
- In `shouldPlayNextResource`, set `_playbackIntent = false` and reset before
  emitting final `.ended`; remove the progress-based end fallback if redundant.
- On expiry, log and emit `.loading`; call `startRecovery` only when opted in.
- Leave post-rebuild `playbackAdvanced` verification unchanged.

Verify: Runner unit tests cover the helper and the ended path; the iOS
integration tests cover healthy and stalled resource loads.

### Android

- Create a watchdog job only while a load attempt is armed, rather than for the
  navigator lifetime.
- Arm from `play()` and `resume()`.
- Include playback index in observed playback changes so automatic resource
  transitions are visible even when state and `playWhenReady` stay unchanged.
- Cancel on forward progress and existing lifecycle/suppression gates.
- On expiry, log and emit `Loading`; call `startRecovery` only when opted in.
- Keep Media3 `playWhenReady` as intent; do not add a duplicate intent flag.

Verify: Kotlin unit tests cover the helper and policy; Android integration tests
cover the same resource-loading outcomes as iOS.

### Web

- Replace the rolling timer with the same one-shot contract.
- Reconcile intent from both Dart commands and navigator `play`/`pause` events,
  covering Media Session controls.
- Arm before automatic advance and explicit cross-resource navigation while
  playback is requested.
- Disarm on forward `positionChanged` and existing lifecycle/error gates.
- Keep the browser `stalled` event as an immediate loading-state signal only;
  it must not arm recovery during established playback.
- On expiry, log and emit `loading`; invoke recovery only when opted in.

Verify: Jest covers commands, Media Session events, resource transitions,
expiry, and opt-in recovery; `bin/typecheck` and
`bin/update_web_example` pass.

### Integration and documentation

Extend the existing loopback server rather than adding another fixture. Run
these cases on the iOS simulator and Android emulator:

- Healthy startup and healthy resource transition disarm without retry.
- With timeout recovery disabled, a second resource that cannot start emits
  `.loading` but no retry.
- With recovery explicitly enabled, the second resource stalls its first request, serves
  the retry, and advances. This proves rebuild restores playback rather than
  merely proving that the timer fires.
- The existing mid-resource stalling fixture produces no watchdog retry after
  initial playback has disarmed it, even when recovery is enabled.
- Final `.ended` and explicit pause remain stable beyond the short test timeout.

Rewrite docs, comments, API reference, and the Unreleased changelog around a
"resource-loading watchdog." State that later mid-resource stalls are left to
the native player and explicit error recovery, while resource-loading recovery
is disabled by default and can be enabled by the consuming application.

Verify: the native integration cases pass without watchdog retries outside the
explicitly enabled recovery case.

## Final gates

- `bin/format`
- `bin/analyze`
- Focused Swift, Kotlin, and Jest tests
- `bin/typecheck`
- `bin/update_web_example`
- iOS no-codesign example build
- Android `:flutter_readium:compileDebugKotlin`
- Native integration matrix above
- `git diff --check`

Physical-device interruption testing is not a release gate for this re-scope:
interruptions only cancel observation and cannot start recovery.

## Acceptance criteria

- First forward progress permanently disarms the current resource attempt.
- A later freeze in that same resource cannot trigger watchdog recovery.
- Playback start and each requested resource transition get one fresh timeout.
- Timeout emits one `.loading` state and one warning.
- Default configuration reports a resource-loading timeout without rebuilding.
- Explicit opt-in starts the existing recovery loop after a loading timeout.
- Opt-in recovery is proven to resume a transiently stalled new resource.
- Explicit player errors keep their existing recovery behaviour.
- Final end clears iOS playback intent and cancels observation.

## Delivery

Use additive commits on the existing fork branch; do not rewrite published
history. Keep the implementation in four reviewable slices:

- tests and policy;
- iOS, Android, and web behavior;
- native integration evidence;
- docs and changelogs.

Do not push or change the pull request until the verification result has been
reported in this task.
