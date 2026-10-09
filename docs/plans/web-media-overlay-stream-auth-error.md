# Web: classify 401/403 in Media Overlay audio sessions

> **✅ Implemented (2026-10-09).** The LYT4 follow-up below is still open.

## Problem

On web, a 401/403 on a sync-narration (Media Overlay) audio resource emits only `TimebasedState.failure`. It never emits `AudioStreamAuthError`, so apps cannot tell an expired stream token from any other failure. Plain audiobooks do emit it.

Seen in LYT4 on 2026-10-09: an audio-only book recovered from a simulated 401; a text + narration book did not.

## Cause

- `initializeMediaOverlayNavigator` calls `FlutterAudioNavigator.create` without a bridge (`flutter_readium/web/src/navigators/FlutterMediaOverlayNavigator.ts:195`).
- `create` only builds the recovery controller when there is no `locatorMapper` and there is a bridge (`flutter_readium/web/src/navigators/FlutterAudioNavigator.ts:810`).
- With no controller, the `error` listener emits `failure` and returns before the HTTP probe runs (`FlutterAudioNavigator.ts:954-959`).

A rejected `play()` is not a separate gap. ts-toolkit's `WebAudioEngine.play()` re-emits the rejection on its `error` event, so it reaches the same listener. The `DOMException` code is 9, not a `MediaError` code, so it classifies as `retry` and the probe runs. The plain-audiobook test below proves this.

## Parity

Static reading only. Not run on a device.

- iOS: `FlutterMediaOverlayNavigator` subclasses `FlutterAudioNavigator`, so the `as? FlutterAudioNavigator` cast in `FlutterReadiumPlugin.swift:527` routes read errors to `handleResourceReadError`. A 401 gives `AudioStreamAuthError`.
- Android: `SyncAudiobookNavigator` extends `AudiobookNavigator` and calls `super.setupNavigatorListeners()`, so `onPlaybackStateChanged` classifies the failure. A 401 gives `AudioStreamAuthError`.

Both native sides also run retry/rebuild recovery for Media Overlay. Web will only classify. That difference stays documented, not fixed here.

## Fix

Classify without rebuild for Media Overlay sessions:

1. Pass the bridge from `initializeMediaOverlayNavigator` (and the guided-navigation path) through to `create`.
2. In `create`, when `locatorMapper` is set and a bridge exists, keep the current `failure` emission but run the probe first. Extract a small `classifyWithProbe(mediaError, href, publication)` from `handleAudioStreamError` so both paths share it.
3. On `fail(code, httpStatus)`: `nav.stop()`, `bridge.emitError(message, code, { href, httpStatus })`, then emit `failure`. On `retry`/inconclusive: emit `failure` with `AudioStreamNetworkError`, as the plain path does when its attempts run out. On `ignore`: do nothing.
4. Latch per session so one bad track emits one error, not one per `error` event. Clear the latch on the next `play()`.
5. Keep the rebuild-based recovery out of scope. The comment at `FlutterAudioNavigator.ts:800` already explains why (mapper cue state cannot resume).

Check that `resolveAudioResourceUrl` resolves against the synthetic publication. Its reading-order hrefs are absolute after `_resolveItemHrefs`, so the probe should hit the real track URL.

## Tests

- `flutter_readium/web/src/__tests__/FlutterAudioNavigatorStreamAuth.test.ts`: 401 via `MediaError` and via rejected `play()`, for plain and Media Overlay sessions. Media Overlay also covers an inconclusive probe, `MEDIA_ERR_ABORTED`, and the one-error-per-failure latch.
- Gates: `npm test`, `bin/typecheck`, `bin/update_web_example`.
- Manual: web example with a sync-narration fixture behind a server that returns 401 for one track.

## Changelog

Under Unreleased: web now reports `AudioStreamAuthError` / `AudioStreamHTTPError` for sync-narration audio, as iOS and Android do.

## LYT4 follow-up

- Bump to the flutter_readium release that carries this fix (LYT4 uses 0.6.1).
- Check that `PlayerService.recoverAudioAuthentication` reopens a text + narration book correctly. It was only proven on an audio-only book.
- Re-run the 2026-10-09 test on "Møgmis" (merkur:libraryid:51032).
