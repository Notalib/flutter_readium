# Web: audio stream recovery for Media Overlay sessions

> **✅ Implemented (2026-10-12).** The LYT4 follow-up below is still open.

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

Both native sides also run retry/rebuild recovery for Media Overlay.

## Fix

Give Media Overlay sessions the same recovery as plain audiobooks:

1. Pass the bridge from `initializeMediaOverlayNavigator` and `initializeGuidedNavigationNavigator` to `create`. With a bridge, `create` builds the recovery controller for every session.
2. Pass the mapper and text callback through `rebuildAndVerifyPlayback`. The mapper only looks up the cue for an audio time in a fixed item list, so a rebuilt navigator keeps the text sync. (An older comment claimed the cue state could not resume. It could.)
3. Pinned `loading`/`failure` states go through the mapper for Media Overlay, so they carry the text locator like every other state.
4. `play()` after a terminal failure: `ReadiumReader` maps a text locator to audio, then calls `FlutterAudioNavigator.recreateAfterFailure`. It rebuilds with the session's mapper, instead of a bare `create` that dropped it.
5. The rebuild keeps the track's media type instead of forcing `audio/mpeg`.

The probe resolves against the synthetic publication. Its reading-order hrefs are absolute after `_resolveItemHrefs`, so it hits the real track URL.

## Tests

- `flutter_readium/web/src/__tests__/FlutterAudioNavigatorStreamAuth.test.ts`: for plain and Media Overlay sessions, 401 via `MediaError` and via rejected `play()`, `MEDIA_ERR_ABORTED`, and network error with rebuild. Media Overlay also checks that the rebuilt navigator, the pinned states and `recreateAfterFailure` keep the text mapping.
- `ReadiumReader.test.ts`: `play()` after failure maps a text locator to audio.
- Gates: `npm test`, `bin/typecheck`, `bin/update_web_example`.
- Not done: a browser run against a real 401.

## LYT4 follow-up

- Bump to the flutter_readium release that carries this fix (LYT4 uses 0.6.1).
- Check that `PlayerService.recoverAudioAuthentication` reopens a text + narration book correctly. It was only proven on an audio-only book.
- Re-run the 2026-10-09 test on "Møgmis" (merkur:libraryid:51032).
