# Native DiViNa Narration Sync Handoff

> **Status:** Phase 1 (narration sync state + manual mode) is implemented and verified
> (compile/analyze/unit-test) on Dart, iOS, Android, and Web. The feature was generalized from
> comic-only auto-pan into a unified **narration manual-mode** for Media Overlay + TTS:
> `FlutterReadium.setNarrationSyncEnabled(bool)` + `onNarrationSyncChanged`, with
> `EPUBPreferences.disableSynchronization` folded in (deprecated). Comic **panel pan/zoom** and the
> JS→native gesture bridge are deferred to Phase 2 — see
> [`native-comic-panel-pan-handoff.md`](native-comic-panel-pan-handoff.md). This document is the
> original brief, retained for reference.

Goal: implement the Web DiViNa comic re-sync behavior for iOS and Android when a DiViNa comic has Sync Narration or Guided Navigation.

This is a handoff for the next agent. Web is the reference implementation and is now considered satisfactory.

## User-visible target

For narrated DiViNa comics on iOS and Android:

1. Audio playback follows cue changes by navigating the comic page and, where feasible, framing the active panel.
2. If the user manually pans/zooms/pages away from narration, Dart receives `onNarrationSyncChanged(false)` so the example app shows the Re-sync button.
3. Tapping Re-sync calls `setComicAutoPan(true)` and the native side immediately reattaches the visual comic view to the active audio cue.
4. `stop()` tears down the timebased navigator cleanly. Re-enabling narration starts from the current visual comic locator with fresh audio/listener state.
5. Public locator streams stay useful for persistence: persist the visual text/page locator separately from the timebased audio/current locator.

## Web reference behavior

Use these files as the behavioral source of truth:

- `flutter_readium/web/src/ReadiumReader.ts`
  - `stop()` destroys and clears Media Overlay / Guided Navigation audio navigators.
  - `audioEnable()` recreates the audio navigator from the current visual locator when no audio navigator exists.
  - `setComicAutoPan(true)` performs a single explicit current-cue re-sync via `_resyncDivinaToCurrentAudioCue()`.
- `flutter_readium/web/src/navigators/FlutterDivinaNavigator.ts`
  - Tracks `autoPanEnabled`, manual override, and last cue region.
  - Emits `updateNarrationSync(false)` on manual gesture and `true` when sync is restored.
  - `panToRegion(region)` pans to active `comicRegion`; `null` means fit whole page.
- `flutter_readium/web/src/navigators/FlutterMediaOverlayNavigator.ts`
  - Emits two locator shapes: detailed/internal cue locators for visual sync and coarse public text locators to avoid page-level locator spam.
- `flutter_readium/web/src/mediaoverlay/syncNarration.ts`
  - Carries `comicRegion` through `Locator.locations.otherLocations` for Guided Navigation panel framing.
- `docs/guides/saving-progress.md`
  - Documents the two-locator persistence model for comics.

Do not reintroduce the old automatic DiViNa re-sync retry burst. Normal playback should prove listener/polling works through real cue events; the Re-sync button is the explicit recovery action.

## Current native state

### iOS

Relevant files:

- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift`
  - `stop` already disposes `timebasedNavigator`, sets it to `nil`, emits `.none`, and clears timebased decorations.
  - `audioEnable` creates `FlutterMediaOverlayNavigator` when `publication.containsSyncNarration` is true, otherwise `FlutterAudioNavigator` for audiobooks.
  - `timebasedNavigator(_:reachedLocator:segmentDuration:isWordRange:)` forwards cue locators to `currentReaderView?.syncToLocator(...)`.
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/navigator/FlutterMediaOverlayNavigator.swift`
  - Maps text locators to audio locators and audio locators back to text/combined locators.
  - Dedupes text sync by `href + cssSelector` using `lastTextSyncKey`.
  - `submitTimebasedPlayerStateToListener` emits combined locators through the timebased state stream.
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/model/FlutterMediaOverlay.swift`
  - Already has DiViNa-aware locator matching comments for image/page anchors.
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/EPUBReaderView.swift`
  - DiViNa currently uses the EPUB reader path. `syncToLocator` is the likely visual-sync hook.

Likely gaps:

- No native method-channel implementation for `setComicAutoPan` / `onNarrationSyncChanged` parity was found in iOS. Add this to the method-channel contract if absent.
- `syncToLocator` may navigate page-level anchors but probably does not expose a native equivalent of Web's panel-level `comicRegion` pan/zoom.
- Need to verify whether Guided Navigation panel geometry is parsed into iOS model objects and preserved on locators. If not, mirror Web's `comicRegion` transport using `Locator.locations.otherLocations` or a native-side cue model field.

### Android

Relevant files:

- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReader.kt`
  - `audioEnable` always disposes previous audio/sync-audio navigators before creating a new one.
  - `stop()` pauses, disposes, and nulls audiobook, sync-audiobook, and TTS navigators, then emits `ReadiumTimebasedState.none()`.
  - `onTimebasedLocationChanged` currently calls `epubSyncToLocator(locator, true)`.
  - `comicNavigator` is available via the typed accessor when the visual navigator is a comic.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/navigators/SyncAudiobookNavigator.kt`
  - Maps audio locator changes to media-overlay text locators.
  - Calls `ReadiumReader.epubSyncToLocator(textLocator, false, mediaOverlay.duration)` for visual sync.
  - Dedupes sync by `href + cssSelector`.
  - Emits timebased current locators mapped back to text-ish/audio-ish locators through `onTimebasedCurrentLocatorChanges`.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/navigators/ComicNavigator.kt`
  - Wraps Readium `ImageNavigatorFragment` for CBZ / DiViNa.
  - Supports page navigation via `goToLocator`, but no panel pan/zoom API exists today.
  - Does not currently report narration sync override state to Dart.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/models/FlutterMediaOverlayItem.kt`
  - Produces `syncTextLocator`, `flutterAudioLocator`, and `skipToAudioLocator`.
  - Does not appear to carry Guided Navigation `comicRegion` panel geometry yet.

Likely gaps:

- `SyncAudiobookNavigator` sends visual sync through EPUB-specific code. For comics, route cue sync to `ComicNavigator` instead of `epubNavigator`.
- `ComicNavigator` needs either a true panel framing implementation or an explicitly documented page-only limitation. Do not fake panel sync with brittle view-tree hacks unless there is a stable `ImageNavigatorFragment` / `PhotoView` hook.
- Native `setComicAutoPan` and `onNarrationSyncChanged` method/event support needs wiring for Android if absent.

## Implementation outline

### 1. Keep lifecycle semantics fresh

iOS and Android are already close:

- iOS `stop` destroys the active timebased navigator.
- Android `stop` disposes and nulls sync audio, and `audioEnable` recreates sync audio.

Preserve that behavior. Do not change native Media Overlay / Guided Navigation stop into pause-only.

### 2. Add native comic sync state API

Implement the Dart-facing methods/events on both native platforms:

- `setComicAutoPan(bool enabled)`
- `onNarrationSyncChanged` event stream (`true` = in sync, `false` = user manually took control)

The Dart API already exists and Web implements it. Keep native semantics identical:

- `false` when the user manually pans/zooms/pages away from narration tracking.
- `true` when a page turn caused by narration or explicit Re-sync restores tracking.
- `setComicAutoPan(true)` clears manual override and immediately syncs to the current audio cue.

### 3. Split public locator emission from internal cue sync

Web uses detailed cue locators internally and coarse public text locators externally to avoid locator spam. Mirror this intent natively:

- Internal sync locator: enough detail to page/panel sync the visual comic view.
- Public text locator: page-level locator suitable for `onTextLocatorChanged` and visual resume.
- Timebased current locator: audio/progress locator suitable for audio resume.

Check current native behavior before editing. iOS already dedupes `reachedLocator`; Android already uses `distinctUntilChangedBy`. The likely remaining work is coarse public text-locator emission for comic cues and carrying panel region internally.

### 4. Implement visual cue sync for comics

Minimum acceptable behavior:

- Cue changes navigate the comic visual navigator to the cue page.
- Re-sync navigates to the current cue page after manual navigation.
- Manual user navigation marks narration as out of sync.

Preferred behavior:

- Cue changes also pan/zoom to the active panel region.
- Re-sync restores both page and panel.

Panel geometry source:

- Guided Navigation `imgref #xywh=pixel:x,y,w,h` should become a platform-native `ComicRegion` equivalent.
- Carry it with the internal cue locator, not the public coarse locator.

Be honest if native upstream image navigators do not expose stable pan/zoom hooks. A page-only implementation with documented limitation is better than a fragile reflection/view-tree manipulation.

### 5. Explicit Re-sync behavior

Do not add a retry burst. Re-sync should be a single operation:

1. Read current sync audio navigator locator/time.
2. Find matching media-overlay/guided-navigation item.
3. Clear manual override.
4. Navigate/pan the comic navigator to that cue.
5. Emit narration sync `true`.

If step 2 fails, log the audio href/time and leave state unchanged.

### 6. Logging

Add targeted debug logs similar to Web:

- audio enable branch: plain audiobook vs sync narration vs guided navigation
- stop/dispose branch and whether a sync-audio navigator existed
- current audio locator changes, throttled/deduped
- cue-to-text mapping result and failures
- comic page navigation/panel sync result
- manual override state changes and explicit Re-sync result

Follow Android's `PluginLog.*` convention: every message starts with the enclosing function name, e.g. `::audioEnable - ...`.

## Validation checklist

Use the example app and the same fixture used for Web (`nota-comic` / narrated DiViNa comic):

1. Open the comic.
2. Start narration; verify page/cue following.
3. Manually navigate or pan away; verify Re-sync button appears.
4. Tap Re-sync; verify page/panel returns to the current narration cue.
5. Stop on page 2, manually navigate to page 3, press play; verify audio starts at page 3 and cue following continues.
6. Verify `onTextLocatorChanged` is page-level/coarse enough to avoid cue spam.
7. Verify `onTimebasedPlayerStateChanged.currentLocator` remains useful for audio resume.
8. Repeat on both Sync Narration and Guided Navigation fixtures if available.

Suggested commands after implementation:

```bash
bin/format
bin/analyze
```

Platform smoke tests:

- iOS: run the example app on a simulator and exercise the checklist manually.
- Android: run the example app on an emulator/device and exercise the checklist manually.

Ask the user to perform any necessary manual tests.

## Non-goals

- Do not change the public Dart persistence contract beyond wiring the existing events/methods natively.
- Do not make plain audiobook `stop()` destructive unless there is a platform-specific reason; the lifecycle concern is for lazy sync narration / guided navigation audio.
- Do not add automatic seek/re-sync retry bursts to mask missing native listener events.
- Do not rely on private upstream view internals for panel pan/zoom without documenting the risk and getting approval.

## Open questions for the next agent

- Can swift-toolkit's DiViNa/EPUB visual stack expose panel pan/zoom cleanly, or is iOS limited to page navigation without JS/helper injection?
- Can kotlin-toolkit `ImageNavigatorFragment` expose a stable zoom/pan hook for a target rectangle, or should Android ship page-level sync first?
- Do native Guided Navigation parsers already preserve `xywh` region data? If not, add it to the native media-overlay item models before attempting visual panel sync.
- Should native public text locator coarsening exactly match Web (`href` + position only), or preserve additional safe fields such as `tocHref`?
