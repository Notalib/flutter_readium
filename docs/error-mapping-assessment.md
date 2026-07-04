# Error Mapping Assessment — Native → Dart Clients

Status: proposal, 2026-07-04. No code changes; decisions marked ⚖️ need sign-off.

## Current state

Two distinct error paths reach clients:

**1. Method-call errors** — `PlatformException` → `ReadiumException.fromPlatformException` ([readium_exceptions.dart](../flutter_readium_platform_interface/lib/src/exceptions/readium_exceptions.dart)). Typed via `OpeningReadiumExceptionType`, matched **by name** (`v.name == ex.code`), though the enum carries a "order must match native code" comment — order-coupling appears stale; needs verification.

**2. Async error events** — `dk.nota.flutter_readium/error` EventChannel → `ReadiumError { message, code?, data?, stackTrace? }`. Three producers, three vocabularies:

| Producer | `code` values | `data` |
|---|---|---|
| iOS | Ad-hoc PascalCase: `TimeBasedNavigatorError`, `TTSUtteranceFailed`, now `AudioStream*` | Freeform string (`"attempt=1/3 href=…"`) |
| Android | `ReadiumExceptionType.wireValue` (opening-error vocabulary) or `Throwable::class.simpleName` | `cause?.message` |
| Web | Rarely set; audio errors emit **nothing** on the channel (state only) | — |

## Problems

1. **No shared vocabulary.** The same failure yields different `code` strings per platform. Tonight's parity work aligns the `AudioStream*` subset; everything else still diverges. `Throwable::class.simpleName` as a code is effectively random.
2. **Stringly-typed everywhere.** Dart `code` is `String?`; clients switch on magic strings with no exhaustiveness, no discoverability, no docs. The example app hardcodes `code == 'AudioStreamRetry'`.
3. **`data` is a convention, not a contract.** Structured facts (attempt, max, href, HTTP status) are packed into a display string nobody can reliably parse.
4. **No severity dimension.** Informational (`AudioStreamRetry`) and terminal (`AudioStreamFailed`) events are distinguishable only by knowing the code list.
5. **Missing context fields.** HTTP status is classified away natively (401 → `AuthError`) — the actual status never reaches the client, though clients may want it for support/telemetry.

## Recommendations (incremental, ordered by value/cost)

**R1 — Dart error-code enum (cheap, do first).** Add `ReadiumErrorCode` to the platform interface: all documented codes + `unknown` fallback, parsed once in `ReadiumError.fromJson` (keep the raw `code` string alongside — non-breaking). Add derived getters: `isTerminal`, `category` (audioStream / tts / opening / navigator / unknown). Document the vocabulary in `docs/api-reference/`. Native sides unchanged.

**R2 — Structured `data` ⚖️ (wire-format change).** Replace freeform `data` strings with a JSON object: `{ "href": …, "attempt": 1, "maxAttempts": 3, "httpStatus": 401 }` (fields optional per code). Dart: `Map<String, dynamic>? details` + typed getters. Breaking only for clients parsing today's strings (unlikely, format is 1 day old). All three platforms touched; do together with the parity work while it's fresh.

**R3 — Severity: derive, don't transport.** `isTerminal`/`isInformational` computed from the code enum in Dart (R1). No wire change needed; skip adding a `severity` field.

**R4 — Verify/fix the `OpeningReadiumExceptionType` coupling.** Matching is by name, so confirm the "order must match" comment is stale and delete it, or fix the real ordinal dependency if one exists on the Android side.

**R5 — Example app as reference consumer.** Switch on the enum: auth → "check your sign-in" dialog, network-terminal → "check connection" dialog + retry button wired to `play()`, `AudioStreamRetry` → transient banner/snackbar instead of log-only.

## Suggested order

R1 + R4 (no wire changes, immediate client value) → R2 + R5 together (one coordinated wire change across iOS/Android/web + example) — ideally in this PR while the `AudioStream*` producers are all being touched anyway, avoiding a second breaking change later.

## Out of scope

- Unifying path 1 and path 2 into a single error surface — larger redesign, low pain today.
- LCP/DRM error taxonomy — not supported yet.
