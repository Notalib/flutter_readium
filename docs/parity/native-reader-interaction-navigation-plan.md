# Native Reader Interaction vs Navigation Plan

## Goal

Separate generic reader interaction from page navigation so manual panning inside
Nota comics does not accidentally trigger native page turns or narration manual
mode.

This should be a separate PR from EPUB image-tap detection. The current PR found
the issue while testing Android MO Nota comics, but the behavior touches shared
reader input semantics across Dart, Android, and iOS.

## Current symptoms

- On Android, manual panning inside a Nota MO comic page can still trigger
  `goForward` / `goBackward` between pages.
- The trigger was isolated to `_onInteraction()` being called from
  `ReadiumReaderWidget`'s `Listener.onPointerMove` path.
- Removing the native notification from pointer-move interaction reduces the
  immediate problem, but it also changes how swipe gestures enter narration
  manual mode.

## Relevant code

- `flutter_readium/lib/reader_widget.dart`
  - `Listener.onPointerMove` classifies small movement as `userSwipe`.
  - `_onInteraction()` hides controls and calls `_channel?.notifyUserNavigation()`.
  - Semantic edge regions call `_channel?.goForward()` / `goBackward()` directly.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/fragments/EpubReaderFragment.kt`
  - Installs `DirectionalNavigationAdapter` on the `OverflowableNavigator`.
  - Readium owns edge-tap / keyboard navigation at the native navigator layer.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReader.kt`
  - Explicit `epubGoForward` / `epubGoBackward` already call
    `enterManualModeIfNarrating(...)` before navigating.
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReaderWidget.kt`
  - Method-channel `notifyUserNavigation` only enters narration manual mode; it
    should not itself page-turn.
- `flutter_readium/assets/_helper_scripts/src/NotaComicBookPage.ts`
  - Nota comic manual pan/zoom uses the cloned image overlay.
  - Touch listeners are passive today, so native navigator input may still see
    the same gesture.

## Working hypothesis

`ReadiumReaderWidget` currently conflates two concepts:

1. Generic interaction: wake lock, hide controls, center/edge tap UI handling.
2. Navigation intent: user intentionally moved to another page and narration
   should enter manual mode.

Now that Android and iOS use native `DirectionalNavigationAdapter`, the Flutter
wrapper should not infer navigation from `onPointerMove`. Native page-turn paths
should own navigation/manual-mode transitions.

The remaining accidental page turn may come from native navigator input seeing
the same touch gesture used by the Nota comic overlay. If so, fixing only Dart is
insufficient; the comic overlay must consume or isolate manual pan gestures.

## Debug checklist

1. Add temporary logs in `reader_widget.dart`:
   - pointer down/move/up
   - whether movement crossed the `userSwipe` threshold
   - whether `_channel.notifyUserNavigation()` was called
2. Add temporary logs in Android `ReadiumReaderWidget`:
   - method-channel `goForward`, `goBackward`, `notifyUserNavigation`
3. Add temporary logs in `ReadiumReader.epubGoForward` / `epubGoBackward` and
   `EpubReaderFragment.goForward` / `goBackward`.
4. Add temporary JS logs in `NotaComicBookPage.ts`:
   - `touchstart`, `touchmove`, `touchend`
   - whether `manualOverrideActive` is true
   - whether the event target is inside `.nota-comicbook-page-container`
5. Reproduce on Android MO Nota comic:
   - pan while zoomed/manual
   - edge tap intentionally
   - swipe intentionally
   - compare event ordering in logs

Expected evidence:

- If `goForward` / `goBackward` method-channel logs fire, Dart/UI code is still
  requesting navigation.
- If native `onPageChanged` happens without method-channel `goForward` /
  `goBackward`, the page turn comes from native navigator input.
- If the native turn disappears when `DirectionalNavigationAdapter` is
  temporarily disabled, Readium input handling is the source.
- If the native turn disappears when the comic overlay consumes manual pan
  events, the source is gesture propagation from the overlay to Readium.

## Proposed implementation direction

### Phase 1: Split Dart interaction semantics

- Rename/split `_onInteraction()` into two explicit concepts:
  - hide controls / refresh wake lock
  - notify navigation/manual-mode intent
- Do not call `notifyUserNavigation` from `onPointerMove`.
- Keep center tap and edge tap behavior explicit.
- Consider deleting `notifyUserNavigation` calls from Flutter entirely once
  native swipe/edge/key navigation is verified to enter manual mode on both iOS
  and Android.

### Phase 2: Make native navigation the authority

- Treat native `goForward` / `goBackward` paths as the authoritative signal for
  manual navigation during narration.
- Verify Android `DirectionalNavigationAdapter` page turns pass through code that
  enters manual mode. If they do not, add a native input listener or navigator
  callback at the Android layer instead of using Flutter pointer movement.
- Do the same verification on iOS.

### Phase 3: Isolate Nota comic manual pan

- When `.nota-comicbook-page-container` is in manual zoom/pan mode, test a
  non-passive touch/pointer listener that calls `preventDefault()` and/or
  `stopPropagation()` for single-finger pan inside the active overlay.
- Keep normal page swipe available when the comic overlay is not in manual mode.
- Avoid blocking pinch gestures needed by the comic helper.

## Acceptance criteria

- Panning inside a zoomed Nota MO comic page does not change EPUB spine/page.
- Intentional native page navigation still works.
- During active narration, intentional page navigation enters manual mode and
  emits `onNarrationSyncChanged(false)`.
- Center tap still toggles controls.
- Edge tap behavior remains intentional and documented.
- Behavior is checked on Android first; iOS parity is verified or explicitly
  documented.

## Suggested validation

- Android manual smoke test with `50272-nota-comics.webpub`:
  - start narration
  - enter manual zoom/pan
  - pan horizontally and vertically inside the page
  - confirm no page turn
  - use intentional edge/swipe page turn
  - confirm page turn and manual-mode event semantics
- Run `bin/format && bin/analyze` before PR.
- If touching Kotlin: run
  `cd flutter_readium/example/android && ./gradlew :flutter_readium:compileDebugKotlin`.
- If touching helper scripts: run `bin/build_helper_scripts` or the equivalent
  npm helper build used by the repo.

## Open questions

- Does Android `DirectionalNavigationAdapter` page navigation pass through
  `ReadiumReader.epubGoForward` / `epubGoBackward`, or does it navigate entirely
  inside the navigator fragment?
- Should Flutter keep semantic edge regions for accessibility only, or should
  native expose accessible page-turn actions directly?
- Is `notifyUserNavigation` still needed after native input paths are verified?
