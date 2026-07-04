# Unified Error Surface — Draft for Discussion

Status: draft, 2026-07-04. Follow-up to [error-mapping-assessment.md](error-mapping-assessment.md) "out of scope" item. No decisions made; ⚖️ marks the ones to take.

## The two paths today

| | Path 1: method-call errors | Path 2: async error events |
|---|---|---|
| Transport | `PlatformException(code, message, details)` on the method channel result | JSON on `dk.nota.flutter_readium/error` EventChannel |
| Dart type | `ReadiumException` hierarchy (`OpeningReadiumException`, …) | `ReadiumError { message, code?, data?, stackTrace? }` |
| Vocabulary | `OpeningReadiumExceptionType` (name-matched) | Free-form strings (being consolidated into `ReadiumErrorCode` by R1) |
| Client ergonomics | try/catch per call | one stream subscription |

Same underlying failures (e.g. an HTTP 401 from a publication server) surface through either path depending on *when* they happen — open time vs streaming time — with different types, codes, and payload shapes. Clients write two error handlers that can't share logic.

## Options

**A. Shared taxonomy, separate transports (recommended).**
Keep both transports — they serve different purposes (request-scoped vs ambient) — but make them speak one language:
1. Both paths use the single `ReadiumErrorCode` vocabulary (R1). Native method-call failures set `PlatformException.code` to the same wire strings the event channel uses; `OpeningReadiumExceptionType` becomes a deprecated alias mapped onto the shared enum.
2. Both paths carry the same structured payload shape (R2's `details` map: `href`, `httpStatus`, `attempt`, …) — `PlatformException.details` and event `data` become the same JSON object contract.
3. Dart converges on **one error value type**: `ReadiumError` (code enum, message, details, `isFatal`/`isInformational`). `ReadiumException` becomes a thin `Exception` wrapper around a `ReadiumError` (kept because idiomatic Dart wants throwables from awaited calls) — one classification, two delivery mechanisms.
4. Each native side gets a single error-construction helper used by both the method-result error path and the event emission path (iOS: one `FlutterReadiumError` factory also producing `FlutterError`; Android: `ReadiumError` also backing `Result.error(...)`; web: the bridge `emitError` + promise rejections share a builder).

Migration cost: moderate, mostly mechanical; breaking for clients catching `OpeningReadiumException` by `type` (pre-1.0, acceptable with a minor bump + changelog). Fully incremental after R1+R2 land — A is essentially "finish what R1/R2 started".

**B. Everything on the error stream.**
Method calls return void/bool; all failures are emitted as events. One handler for everything.
Rejected in draft: loses request↔error association (which call failed?), makes awaited flows (`openPublication`) awkward, and is the largest client break for the least gain.

**C. Result-type returns.**
Methods return a sealed `Result<T, ReadiumError>`. Explicit, no exceptions.
Rejected in draft: fights Dart/plugin idiom (async throws), touches every method signature, churns every consumer callsite. Not worth it pre-1.0 unless a broader API redesign happens anyway.

## Proposed shape (Option A end-state)

```dart
// One value type, both paths:
class ReadiumError {
  final ReadiumErrorCode code;     // shared enum, R1
  final String rawCode;            // wire string, forward-compat
  final String message;
  final Map<String, Object?>? details; // R2 shape: href, httpStatus, attempt…
  bool get isFatal;                // derived from code
  bool get isInformational;
}

// Throwable wrapper for awaited calls (path 1):
class ReadiumException implements Exception {
  final ReadiumError error;
}

// Path 2 unchanged in shape:
Stream<ReadiumError> get onErrorEvent;
```

## ⚖️ Decisions needed

1. Adopt Option A? (B/C documented as rejected unless you disagree.)
2. Deprecation strategy for `OpeningReadiumExceptionType` / typed exception subclasses: alias-and-deprecate for one release, or hard-cut in the next minor (pre-1.0)?
3. Keep `stackTrace` on the wire? It's native-side trace, rarely actionable for Dart clients — proposal: drop from the contract, keep in native logs.
4. Timing: Option A step 1–2 fall out of R1+R2 nearly for free; steps 3–4 (type convergence + native helpers) are a separate PR. Do them immediately after, or park until a client actually needs it?

## Affected surface (Option A, steps 3–4)

- `flutter_readium_platform_interface`: `readium_exceptions.dart` (rework), `method_channel_flutter_readium.dart` (single decode path).
- iOS: error construction sites in `FlutterReadiumPlugin.swift` (~8 `FlutterError(...)` sites), `ReadiumErrors+UserError.swift`, `FlutterReadiumError`.
- Android: `PublicationError.kt`, `ReadiumErrorEventChannel.kt`, method-channel error results in `FlutterReadiumPlugin`/`ReadiumReader`.
- Web: `ReadiumBridge.ts` error emission + promise-rejection payloads.
- Example app: single error handler demo replacing the split handling.
