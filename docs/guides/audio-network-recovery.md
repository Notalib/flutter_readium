# Audio Network Recovery

When you stream a remote audiobook (reading-order resources fetched over HTTP), the
connection can drop, throttle, or return an auth/HTTP error mid-playback. The plugin
detects these, attempts to recover automatically, and reports progress on the error
stream so your app can keep the user informed. This guide covers what those events look
like and how to configure the recovery behaviour.

For the full code vocabulary and the structured `details` payload, see
[error-codes.md](../api-reference/error-codes.md). For opening errors and the general
error model, see [error-handling.md](error-handling.md).

## The recovery lifecycle

1. **Transient failure or resource-loading stall** — a retryable network error, or playback
   failing to advance after play/resume or a new reading-order resource. The plugin does not
   surface this as a hard failure; by default it starts recovering.
2. **Retrying** — for each attempt it emits an **informational** `AudioStreamRetry`
   event (`error.codeEnum.isInformational == true`) carrying `attempt` / `maxAttempts`,
   while the timebased state stays `loading`. Backoff grows between attempts.
3. **Resolved** — if an attempt succeeds, playback resumes from the last position and
   normal state emissions continue. No further error events.
4. **Terminal failure** — if all attempts are exhausted, the plugin emits a **fatal**
   coded event (e.g. `AudioStreamAuthError`, `AudioStreamNetworkError`) together with
   `TimebasedState.failure`. Calling `play()` afterwards retries from the last position.

## Handling it in your app

Subscribe to `onErrorEvent` and branch on the typed code. The category tells you it is
an audio-stream event; `isInformational` separates the transient retry from a terminal
failure:

```dart
_errorSub = FlutterReadium().onErrorEvent.listen((error) {
  if (error.codeEnum.category != ReadiumErrorCategory.audioStream) {
    log('Reader error [${error.code}]: ${error.message}');
    return;
  }

  if (error.codeEnum.isInformational) {
    // Transient: recovery in progress. Show a non-blocking indicator.
    final attempt = error.attempt, max = error.maxAttempts;
    showReconnectingBanner(
      attempt != null && max != null ? 'Reconnecting ($attempt/$max)…' : 'Reconnecting…',
    );
  } else {
    // Terminal: recovery gave up. Offer an actionable retry.
    showFailureDialog(
      message: switch (error.codeEnum) {
        ReadiumErrorCode.audioStreamAuthError => 'Authentication error, login may have expired.',
        ReadiumErrorCode.audioStreamRangeNotSupported => 'This server does not support audio seeking.',
        _ => 'There was a problem with your connection.',
      },
      onRetry: () => FlutterReadium().play(), // resumes from the last position
    );
  }
});
```

Always cancel the subscription in `dispose()`. The example app's
[`player.page.dart`](../../flutter_readium/example/lib/pages/player.page.dart) is a
complete reference implementation (retry snackbar + terminal dialog with a working Retry
button).

Read `attempt` / `maxAttempts` / `httpStatus` / `href` through the typed getters on
`ReadiumError` rather than reaching into `details` directly.

## Configuring recovery

Tune the retry budget, backoff, and stall sensitivity with `AudioRecoveryPolicy`:

```dart
await FlutterReadium().setAudioRecoveryPolicy(
  const AudioRecoveryPolicy(
    maxAttempts: 5,          // more attempts on flaky networks
    stallTimeoutSeconds: 30, // wait longer for initial resource progress
    recoverOnResourceLoadingTimeout: true, // rebuild after a loading timeout
  ),
);
```

- Set it **once**, before opening the publication you want it to apply to. Existing
  audio sessions keep the policy captured when their navigator was created.
- Defaults are `maxAttempts: 3`, `backoffBaseSeconds: 1.0`, `stallTimeoutSeconds: 20.0`,
  `connectionTimeoutSeconds: 10.0`, and `recoverOnResourceLoadingTimeout: false`.
  Explicit player errors still recover automatically; a resource-loading timeout reports
  `loading` without rebuilding unless recovery is enabled. `connectionTimeoutSeconds` is the budget for each phase of a
  recovery attempt: on Android/web it bounds the (asynchronous) navigator rebuild, and
  on all three platforms it separately bounds the post-rebuild window in which playback
  must be observed to advance before the attempt is abandoned.
- The resource-loading watchdog disarms permanently after playback advances by more than 100 ms.
  Later mid-resource stalls are left to the native player and explicit error recovery.
  Set `recoverOnResourceLoadingTimeout` to `true` when a suspected loading timeout should also
  rebuild the navigator. Explicit player errors recover regardless of this setting.
- Raise `stallTimeoutSeconds` if legitimate startup or chapter-boundary loading trips the watchdog;
  lower it to report sooner. Field semantics:
  [error-codes.md#audiorecoverypolicy](../api-reference/error-codes.md#audiorecoverypolicy).

## Platform notes

Supported on iOS, Android, and Web. On Web the browser does not expose HTTP status codes
for media loads, so auth/HTTP classification relies on a short diagnostic fetch probe;
when it is inconclusive the failure surfaces as `AudioStreamNetworkError` rather than a
more specific code. Detail: [error-codes.md](../api-reference/error-codes.md).
iOS audio streaming requires byte-range support from the remote audio server; if a range
request is rejected, the terminal error is `AudioStreamError` with `details.reason: "rangeNotSupported"`.
