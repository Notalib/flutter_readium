# Error codes

`ReadiumErrorCode` (platform interface) is a typed classification of the wire `code` string carried by two distinct error paths — see [streams-events.md](./streams-events.md#onerrorevent) for `ReadiumError` and `readium_exceptions.dart` for `OpeningReadiumException`. It never replaces the raw string fields (`ReadiumError.code`, `OpeningReadiumException.type`); parsing is additive and non-breaking.

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

| `ReadiumErrorCode` | Wire string(s) | Platforms | Category | Fatal? | Meaning |
|---|---|---|---|---|---|
| `formatNotSupported` | `formatNotSupported` | iOS, Android, web | opening | fatal | Publication format not supported by the toolkit |
| `unsupportedScheme` | `unsupportedScheme` | iOS, Android, web | opening | fatal | URL scheme not supported when opening |
| `readingError` | `readingError` | iOS, Android, web | opening | fatal | Generic read failure while opening a publication |
| `notFound` | `notFound` | iOS, Android, web | opening | fatal | Publication resource not found |
| `forbidden` | `forbidden` | iOS, Android, web | opening | fatal | Access to the publication resource is forbidden |
| `unavailable` | `unavailable` | iOS, Android, web | opening | fatal | Publication temporarily unavailable |
| `incorrectCredentials` | `incorrectCredentials` | iOS, Android, web | opening | fatal | Credentials rejected while opening a protected publication |
| `audioStreamRetry` | `AudioStreamRetry` | iOS, Android, web | audioStream | **informational** | Automatic connection recovery in progress after a transient network error, or a detected playback stall; playback state pinned to loading |
| `audioStreamFailed` | `AudioStreamFailed` | iOS, Android | audioStream | fatal | Generic recovery-exhausted fallback; call `play()` to retry manually. Recovery carries through the originally classified code where possible (e.g. `audioStreamNetworkError`, `audioStreamAuthError`), so this is only seen for failure shapes that don't map to a more specific code |
| `audioStreamAuthError` | `AudioStreamAuthError` | iOS, Android, web | audioStream | fatal | HTTP 401/403 fetching an audio resource |
| `audioStreamHttpError` | `AudioStreamHTTPError` | iOS, Android, web | audioStream | fatal | Other non-5xx HTTP error fetching an audio resource |
| `audioStreamNetworkError` | `AudioStreamNetworkError` | iOS, Android, web | audioStream | fatal | Unclassified network-layer failure streaming audio |
| `audioStreamFileError` | `AudioStreamFileError` | iOS | audioStream | fatal | Local filesystem error reading an audio resource |
| `audioStreamError` | `AudioStreamError` | iOS, web | audioStream | fatal | Unclassified/default terminal audio streaming failure |
| `ttsUtteranceFailed` | `TTSUtteranceFailed` | iOS | tts | fatal | A single TTS utterance failed to synthesize/play |
| `timeBasedNavigatorError` | `TimeBasedNavigatorError` | iOS | navigator | fatal | Generic time-based (audio/TTS) navigator failure not covered by a more specific code |
| `didFailToLoadResource` | `DidFailToLoadResource` | iOS | navigator | fatal | Visual reader (EPUB/PDF) failed to load a resource |
| `unknown` | any unrecognised string, or missing `code` | all | unknown | fatal | Fallback — includes Android's `Throwable::class.simpleName`, which is not an enumerable vocabulary |

Android does not currently emit `AudioStreamFailed` failures beyond backoff, `AudioStreamFileError`, or `AudioStreamError` — its ExoPlayer-backed classifier only distinguishes HTTP-layer failures (auth/HTTP/network); anything else falls back to `AudioStreamNetworkError`. Web similarly cannot distinguish `AudioStreamAuthError`/`AudioStreamHTTPError` from a generic network failure via `HTMLMediaElement` alone and falls back to `AudioStreamNetworkError` unless an HTTP probe classifies the status.

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

Set once — it applies to the next-opened publication and to any in-flight recovery loop, not to an already-running attempt sequence. Defaults reproduce the recovery behaviour that shipped before this policy existed, so an unconfigured consumer sees no change.

**Stall watchdog**: recovery was originally error-driven only — a dropped connection errors and recovers, but a *throttled* connection that keeps bytes trickling in never errors and playback could sit in `Buffering`/`Loading` forever. All three platforms now also watch for the offset failing to advance for `stallTimeoutSeconds` while playback is intended, and synthesize a retryable `audioStreamRetry` into the same recovery path a real error would take. On web, the browser's native `stalled` event (fires quickly, ~3s) is only an early UI signal for a buffering indicator — it does not itself trigger recovery, which still waits for the full `stallTimeoutSeconds` of a frozen offset, matching iOS/Android.
