# Native Comic Panel Pan/Zoom Handoff

**Type:** Cross-platform parity
**Platforms affected:** iOS, Android
**Estimated effort:** M-L

## Goal

Bring comic cue framing on native platforms closer to the existing web behavior for narrated
DiViNa / Guided Navigation publications.

The narration-sync infrastructure is already implemented: manual mode, Re-sync, and the shared
`setNarrationSyncEnabled(bool)` / `onNarrationSyncChanged` API are already live. This plan only
covers the remaining visual-sync gap: when a narrated comic cue targets a panel region, iOS and
Android should follow it at least at page level, and ideally by panning/zooming to the active
panel.

## Current state

- **Implemented already**
  - narration sync lifecycle (`stop`, `play`, re-enable sync)
  - manual mode state transitions and Re-sync UI semantics
  - unified Dart API for narration sync state
  - web reference behavior for panel framing
- **Still missing / uncertain on native**
  - transport and use of `imgref#xywh=pixel:...` panel geometry for visual sync
  - native panel framing parity for DiViNa / Guided Navigation cues
  - a clear native contract for whether comic cue sync is page-only or panel-accurate

## Reference behavior on web

Use these files as the behavioral source of truth:

- `flutter_readium/web/src/ReadiumReader.ts`
- `flutter_readium/web/src/navigators/FlutterDivinaNavigator.ts`
- `flutter_readium/web/src/mediaoverlay/syncNarration.ts`
- `docs/guides/saving-progress.md`

The key expectations are:

1. Cue changes follow the active comic page.
2. When panel geometry is available, the reader frames the active panel.
3. Manual user pan/zoom exits sync and surfaces `onNarrationSyncChanged(false)`.
4. Re-sync snaps back to the current cue.

## Native gaps to close

### iOS

Relevant files:

- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/navigator/FlutterMediaOverlayNavigator.swift`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/model/FlutterMediaOverlay.swift`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/model/guided-nav/`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/reader/EPUBReaderView.swift`

Open questions:

- Does the current iOS visual sync path only page to the correct image/resource, or can it safely
  frame a panel within that page?
- Is Guided Navigation `imgref` geometry already preserved deeply enough to drive native framing?
- If not, should that data ride in `Locator.locations.otherLocations`, or stay in a native-only cue
  model?

### Android

Relevant files:

- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReader.kt`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/navigators/SyncAudiobookNavigator.kt`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/navigators/ComicNavigator.kt`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/models/FlutterMediaOverlayItem.kt`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/models/GuidedNavigation*.kt`

Open questions:

- Can `ComicNavigator` expose a stable target-rect pan/zoom API on top of the native image viewer?
- If not, should Android ship an explicit page-level-only sync guarantee for comics first?
- Is the existing PhotoView-related infrastructure enough for safe panel framing, or does it only
  solve swipe-vs-pan conflict?

## Implementation direction

### 1. Preserve the existing sync-state contract

Do not reopen the already-landed narration-sync API shape. This follow-up should reuse:

- `FlutterReadium.setNarrationSyncEnabled(bool)`
- `FlutterReadium.onNarrationSyncChanged`
- the current stop/play/manual-mode semantics

### 2. Separate page-following from panel-framing

Treat these as two explicit levels of support:

- **Minimum acceptable:** cue changes reliably navigate to the correct comic page; Re-sync returns
  to the current cue page.
- **Preferred:** cue changes also frame the active panel when `imgref` geometry exists.

If panel framing turns out to be brittle on a platform, document and ship the page-level contract
instead of faking full parity.

### 3. Preserve public locator sanity

As on web, keep the external consumer-facing locator streams useful:

- public visual locators should remain coarse enough for persistence
- internal cue-sync data can be richer if needed
- timebased current locators should still remain usable for audio resume

### 4. Be explicit about geometry transport

Guided Navigation `imgref` regions are the likely input for panel framing. Decide and document
where that geometry lives while syncing:

- native-only cue model
- `Locator.locations.otherLocations`
- another internal bridge structure

Whichever path is chosen, keep it separate from the public persistence contract unless a real
consumer need appears.

## Validation checklist

Use the example app and a narrated comic/DiViNa fixture:

1. Start narration and verify cue-following keeps the correct comic page in view.
2. If panel framing is implemented, verify the active panel is framed, not just the whole page.
3. Manually pan/zoom/page away and confirm `onNarrationSyncChanged(false)` is emitted.
4. Tap Re-sync and verify the reader returns to the current cue.
5. Confirm `onTextLocatorChanged` remains coarse enough to avoid cue spam.
6. Confirm `onTimebasedPlayerStateChanged.currentLocator` is still usable for resume.

Suggested follow-up commands after implementation:

```bash
bin/format
bin/analyze
cd flutter_readium/example/android && ./gradlew :flutter_readium:compileDebugKotlin
cd flutter_readium/example && fvm flutter build ios --no-codesign
```

## Non-goals

- Reworking the public Dart sync-state API
- Adding automatic re-sync retry bursts
- Introducing fragile private-view hacks just to claim panel-level parity
