# Audio Recovery — Configurable Policy + Stall Watchdog

Status: plan, 2026-07-04. Follow-up to the audio error-recovery work (`docs/parity/ios-audio-error-recovery-plan.md`). Delegable to an implementation model. Manual validation delegated to the user (Link Conditioner).

## Problem

Recovery today is **error-driven only**. A dropped connection eventually errors and recovers correctly (verified on Android). But a *throttled* connection (Link Conditioner on, not off) keeps bytes trickling in, so the player never errors — it sits in `Buffering`/`Loading` forever and recovery never starts.

- **Android**: `startRecovery` fires only from `AudioNavigator.State.Failure` in `onPlaybackStateChanged`. No stall path.
- **iOS**: `startRecovery` fires only from `handleResourceReadError` (container-wrapper read failures). No `AVPlayer` stall observation.
- **Web**: has a browser `stalled` event (~3s, fixed) routed to recovery, but no policy-driven timeout.

Also: recovery knobs (`maxAttempts`, backoff) are **hardcoded** per platform with no consumer-facing configuration.

## Goal

1. One consumer-configurable `AudioRecoveryPolicy` (Dart → all three platforms), defaults preserving current behaviour.
2. A **stall watchdog** on iOS + Android (and policy-aligned on web): if the player *should* be playing but the offset hasn't advanced for `stallTimeout`, synthesize a retryable error and enter the existing recovery loop.

## Config model

New plugin-owned model in `flutter_readium_platform_interface` (flat **Map** serialization, per bridge rules — not `json.encode`):

```dart
class AudioRecoveryPolicy {
  final int maxAttempts;          // default 3   (current hardcoded value)
  final double backoffBaseSeconds;// default 1.0 (current: 1s/2s/4s = base * 2^(n-1))
  final double stallTimeoutSeconds;// default 20.0 (NEW; must exceed normal seek/chapter buffering)
  // toJson() -> Map<String, Object?>; const defaults; copyWith; props.
}
```

Surface: `FlutterReadium().setAudioRecoveryPolicy(AudioRecoveryPolicy)` on the platform interface + `MethodChannelFlutterReadium` (new method-channel call `setAudioRecoveryPolicy`, payload = the map). Stored plugin-side; navigators read it at construction and the recovery loop reads current values. Applies to the next-opened publication + in-flight recovery. **No mid-stream reconfiguration** (avoid the complexity until a use case exists).

Defaults must reproduce today's behaviour exactly, so an unconfigured consumer sees no change.

> ⚙️ `connectionTimeout` (per-attempt HTTP/data-source timeout) is deliberately **out of scope** for v1. The stall watchdog fires on a bounded deadline regardless of the underlying player's internal HTTP retry, so it already cures "loading forever". Per-platform HTTP timeout tuning (ExoPlayer `DataSource`/`LoadErrorHandlingPolicy`, AVURLAsset options) is the most divergent knob — add later only if a consumer needs faster hard-failure surfacing.

## Stall watchdog — semantics (shared across platforms)

A stall = **all** of:
- Playback *intent* is on (`playWhenReady` / rate>0 / `.waitingToPlayAtSpecifiedRate`), AND
- offset has not advanced by >100ms for `stallTimeout`, AND
- not currently `isRecovering` / terminally failed, AND
- not paused/ended/seeking-settle within the timeout.

On stall → synthesize a **retryable** error (classified `.retry`, so it maps to `AudioStreamRetry`) → call `startRecovery`. The existing loop owns attempts/backoff/terminal. Exhaustion → terminal (see task 5).

Implementation: reset a deadline on each offset advance; a lightweight 1s poll (or timer) checks the deadline. Reuse each platform's existing offset-delta logic (`playbackAdvanced`) — factor the "did offset advance?" check into a shared helper so the watchdog and the post-rebuild verify share it.

## Tasks

1. **platform_interface** — add `AudioRecoveryPolicy` model (+ tests: toJson/fromJson/copyWith/defaults), `setAudioRecoveryPolicy` on `FlutterReadiumPlatform` + `MethodChannelFlutterReadium`. Method-channel contract doc updated.
2. **Android** — parse the policy in the plugin, feed `recoveryPolicy` from it; add stall watchdog coroutine in `AudiobookNavigator` (offset-advance deadline; factor shared advance-check with `playbackAdvanced`); synthesize retryable error → `startRecovery`. Guard against firing while paused/recovering.
3. **iOS** — same: read policy into `AudioRecoveryPolicy` struct; add watchdog observing `timeControlStatus` + offset in `FlutterAudioNavigator`; synthesize retryable `ReadError` → `startRecovery`.
4. **Web** — read policy into `AudioRecoveryPolicy`; gate the `stalled`→escalation on `stallTimeout` (offset-frozen check via `timeupdate`) instead of the raw browser event, for parity. Note: the browser's native `stalled` event (~3s) is only an early *detection* signal that data has stopped flowing — it is not the escalation threshold; escalation still waits for the full `stallTimeout` like the other platforms, so all three present a consistent ~`stallTimeout` × `maxAttempts` UX bar.
5. **Terminal-code specificity (from testing)** — carry the classified retry code through to `enterTerminalFailure`/`enterFailureState` so a network stall/drop ends as `AudioStreamNetworkError`, not generic `AudioStreamFailed`. All three platforms. (Example UX already maps both to the connection message — no example change required.)
6. **Docs/changelog** — `AudioRecoveryPolicy` under Added (consumer-visible); note the stall watchdog behaviour change.

## Verification

- Unit: policy (de)serialization (Dart); stall-detection helper where unit-testable (Android/iOS/web).
- Compile gates: `flutter build ios --no-codesign` (example), `:flutter_readium:compileDebugKotlin`, `bin/typecheck` + `bin/update_web_example`.
- `bin/format` + `bin/analyze`; `ktlint --format` on touched Kotlin.
- **Manual (user)**: Link Conditioner *throttle* (not off) mid-stream → expect `AudioStreamRetry` within ~`stallTimeout`, then either recovery or terminal `AudioStreamNetworkError`. Confirm a healthy slow-ish network + normal chapter boundary does **not** false-trigger.

## Out of scope / flagged

- `connectionTimeout` per-platform HTTP tuning (see note above).
- Mid-stream policy reconfiguration.
- False-positive tuning of `stallTimeout` default (20s chosen so 3 default attempts total ~60s; user to confirm against real network behaviour during manual validation).
