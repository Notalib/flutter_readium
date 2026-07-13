# Error codes

`ReadiumErrorCode` (platform interface) is a typed classification of the wire `code` string carried by two distinct error paths — `ReadiumException.error` for awaited failures and `ReadiumError` for stream events. It never replaces the raw `code` string; parsing is additive and non-breaking.

```dart
reader.onErrorEvent.listen((error) {
  switch (error.codeEnum.category) {
    case ReadiumErrorCategory.audioStream:
      if (error.codeEnum.isInformational) {
        showRetryBanner(); // AudioStreamRetry: automatic recovery in progress
      } else {
        showAudioErrorDialog(error.codeEnum);
      }
    case ReadiumErrorCategory.tts:
    case ReadiumErrorCategory.navigator:
    case ReadiumErrorCategory.opening:
    case ReadiumErrorCategory.unknown:
      log('Reader error [${error.code}]: ${error.message}');
  }
});
```

`ReadiumErrorCode.fromWire(String?)` parses case-insensitively and never throws — an unrecognised or missing code maps to `unknown`.

## Vocabulary

This is a client-actionable, guaranteed-cross-platform set: every code below is either
emitted by all three platforms, or its absence on a platform is a documented,
honest limitation (see the Per-platform limitations section) rather than an
oversight. Finer-grained distinctions that a client wouldn't branch on differently
(e.g. *why* a resource read failed, *why* an audio stream errored) live in
`details.reason` instead of a separate wire code — see below.

| `ReadiumErrorCode` | Wire string | Platforms | Category | Fatal? | Meaning |
|---|---|---|---|---|---|
| `formatNotSupported` | `formatNotSupported` | iOS, Android, web | opening | fatal | Publication format not supported by the toolkit |
| `unsupportedScheme` | `unsupportedScheme` | iOS, Android, web | opening | fatal | URL scheme not supported when opening |
| `readingError` | `readingError` | iOS, Android, web | opening | fatal | Generic read failure while opening a publication |
| `notFound` | `notFound` | iOS, Android, web | opening | fatal | Publication resource not found |
| `forbidden` | `forbidden` | iOS, Android, web | opening | fatal | Access to the publication resource is forbidden |
| `unavailable` | `unavailable` | iOS, Android, web | opening | fatal | Publication temporarily unavailable |
| `incorrectCredentials` | `incorrectCredentials` | iOS, Android, web | opening | fatal | Credentials rejected while opening a protected publication |
| `audioStreamRetry` | `AudioStreamRetry` | iOS, Android, web | audioStream | **informational** | Automatic connection recovery in progress after a transient network error, or a detected playback stall; playback state pinned to loading |
| `audioStreamAuthError` | `AudioStreamAuthError` | iOS, Android, web | audioStream | fatal | HTTP 401/403 fetching an audio resource |
| `audioStreamHttpError` | `AudioStreamHTTPError` | iOS, Android, web | audioStream | fatal | Other non-5xx HTTP error fetching an audio resource |
| `audioStreamNetworkError` | `AudioStreamNetworkError` | iOS, Android, web | audioStream | fatal | Unclassified network-layer failure streaming audio; also the Android recovery-exhausted fallback for every non-HTTP failure shape (ExoPlayer doesn't distinguish range/filesystem causes) |
| `audioStreamError` | `AudioStreamError` | iOS, web | audioStream | fatal | Unclassified/default terminal audio streaming failure. iOS pairs this with `details.reason: "rangeNotSupported"` (server rejected byte-range streaming) or `"fileSystem"` (local filesystem error); web emits it bare for a `MEDIA_ERR_DECODE`. Not emitted by Android — see above |
| `ttsUtteranceFailed` | `TTSUtteranceFailed` | iOS, Android | tts | fatal | A single TTS utterance failed to synthesize/play (ambient error-channel event, not a method-channel result) |
| `voiceNotFound` | `VoiceNotFound` | iOS, web | tts | fatal | `ttsSetVoice` was called with a voice identifier the platform doesn't have. Not emitted by Android — see Per-platform limitations |
| `ttsError` | `TTSError` | iOS, Android | tts | fatal | Generic TTS synthesis/playback failure not covered by a more specific code |
| `searchError` | `SearchError` | iOS, Android | navigator | fatal | Full-text search failed. Not emitted by web — see Per-platform limitations |
| `noPublicationOpened` | `NoPublication` | iOS, Android, web | navigator | fatal | Navigator operation attempted with no publication currently open |
| `resourceReadError` | `ResourceReadError` | iOS, Android, web | navigator | fatal | A publication resource failed to load/decode. Pairs with `details.reason` — see below |
| `unknown` | any unrecognised string, or missing `code` | all | unknown | fatal | Fallback — includes Android's `PublicationError.Unknown`, which is not an enumerable vocabulary member |

`InvalidArgument` is deliberately **not** part of `ReadiumErrorCode`: it means the
*caller* passed malformed/missing/wrong-typed arguments to a method-channel call
(e.g. an unparseable locator, a missing required argument), not a Readium/domain
failure. All three platforms emit it, and the Dart method-channel wrapper passes it
through as a raw `PlatformException` instead of wrapping it in `ReadiumException` —
so `e.codeEnum` is not the right tool for it; check `e.code == 'InvalidArgument'`
directly if you need to distinguish caller bugs from domain errors.

### `details.reason`

Several codes above are intentionally coarse; a `reason` field in `details` (wire
field `data.reason`) carries the finer distinction a producer *can* make without
adding a new wire code a client would have to branch on identically anyway:

| Code | `reason` values | Platforms |
|---|---|---|
| `audioStreamError` | `rangeNotSupported`, `fileSystem` | iOS only (Android doesn't reach this code; web's `AudioStreamError` is decode-only and doesn't set a reason) |
| `resourceReadError` | `notFound`, `cache` | iOS, Android. Web uses `notFound` and `urlResolution` (no on-disk cache step, so no `cache` reason); its `goTo`-navigation-failure and Media Overlay manifest-deserialization sites use `navigation` and `manifestDeserialization` respectively. Short tokens, but still producer-specific — don't assume every platform sets the same set for a given code |

`reason` is optional and producer-specific; treat it as a hint for logging/telemetry,
not as a value to switch on across platforms until every producer agrees on a shared
short-token set.

### Per-platform limitations

Some vocabulary members can't be honestly emitted on every platform given upstream
toolkit constraints. These are documented gaps, not bugs:

- **`voiceNotFound` — not emitted by Android.** Upstream `AndroidTtsEngine` silently
  falls back to a default voice when the requested `voiceURI` doesn't resolve; there
  is no error path to hook into. iOS resolves synchronously and can detect a miss.
  Web's per-language voice mapping is resolved lazily against
  `speechSynthesis.getVoices()` at speak time (the list can legitimately be empty at
  call time before the browser fires `voiceschanged`), so a miss is only reported for
  the immediate, non-lazy `voiceURI` path — a lazy per-language miss can't be
  distinguished from "not loaded yet" without false positives.
- **`searchError` — not emitted by web.** The web navigator has no full-text search
  implementation yet; there's nothing to fail.

Any unrecognized or non-HTTP transport error on all three platforms (e.g. an ExoPlayer socket error not wrapped as an `HttpError` on Android, an `HTMLMediaElement` error with no usable code on web, or an ad-hoc native failure on iOS) is treated as retryable rather than an immediate terminal failure, and only surfaces as the fatal `audioStreamNetworkError` fallback once recovery attempts are exhausted. Android's ExoPlayer-backed classifier only distinguishes HTTP-layer failures (auth/HTTP/network) from that fallback, so it never emits `audioStreamError`. Web similarly cannot distinguish `AudioStreamAuthError`/`AudioStreamHTTPError` from a generic network failure via `HTMLMediaElement` alone, falling back to `AudioStreamNetworkError` unless an HTTP probe classifies the status.

`isFatal` and `isInformational` are exact complements — `isInformational` is `true` only for `audioStreamRetry`.

## Structured `details` payload

`ReadiumError.details` (wire field: `data`) is a JSON object with producer-specific optional fields — never a freeform string:

| Field | Type | Meaning |
|---|---|---|
| `href` | string | Resource href the error relates to |
| `attempt` | int | Current retry attempt number (`audioStreamRetry`) |
| `maxAttempts` | int | Retry budget (`audioStreamRetry`) |
| `httpStatus` | int | HTTP status that triggered the error, when known |

All fields are optional; a producer omits the field entirely when nothing applies. Prefer the typed getters (`error.href`, `error.attempt`, `error.maxAttempts`, `error.httpStatus`) over reading `details` directly. A `null` `details` means no structured payload was sent.

`ReadiumError.fromJson` tolerates a stale native side still sending `data` as a freeform string (pre-R2 wire format) by wrapping it as `{"message": <string>}` — it never throws on a legacy payload.

## `AudioRecoveryPolicy`

Configures the automatic audio-stream error recovery loop shared by the iOS/Android/web audio navigators — retry attempts, exponential backoff, and stall detection:

```dart
await FlutterReadium().setAudioRecoveryPolicy(
  const AudioRecoveryPolicy(maxAttempts: 5, stallTimeoutSeconds: 15),
);
```

| Field | Default | Meaning |
|---|---|---|
| `maxAttempts` | `3` | Automatic recovery attempts before entering a terminal failure state |
| `backoffBaseSeconds` | `1.0` | Base delay between attempts (`backoffBaseSeconds * 2^(attempt-1)`, i.e. 1s/2s/4s with the default) |
| `stallTimeoutSeconds` | `20.0` | How long playback can go without its offset advancing (while intended to be playing) before a stall is treated as a retryable error |
| `connectionTimeoutSeconds` | `10.0` | Budget for each phase of a single recovery attempt: on Android/web (where rebuilding the player is asynchronous) it bounds the navigator rebuild itself, and on all three platforms it separately bounds the post-rebuild window in which playback must be observed to advance before the attempt is abandoned and the loop moves on (next attempt, or terminal) |

Set once — it applies to the next-opened publication and to any in-flight recovery loop, not to an already-running attempt sequence. Defaults reproduce the recovery behaviour that shipped before this policy existed, so an unconfigured consumer sees no change.

**Stall watchdog**: recovery was originally error-driven only — a dropped connection errors and recovers, but a *throttled* connection that keeps bytes trickling in never errors and playback could sit in `Buffering`/`Loading` forever. All three platforms now also watch for the offset failing to advance for `stallTimeoutSeconds` while playback is intended, and synthesize a retryable `audioStreamRetry` into the same recovery path a real error would take. On web, the browser's native `stalled` event (fires quickly, ~3s) is only an early UI signal for a buffering indicator — it does not itself trigger recovery, which still waits for the full `stallTimeoutSeconds` of a frozen offset, matching iOS/Android.
