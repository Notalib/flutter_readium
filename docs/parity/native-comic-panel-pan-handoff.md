# Phase 2 — Comic panel pan/zoom on native (EPUB+MediaOverlay Nota comics)

Handoff for the next agent. **Phase 1 (narration sync state + manual mode) is implemented and
verified** (compile/analyze/unit-test) on Dart, iOS, Android, and Web — see
`native-divina-sync-handoff.md` for the original brief and the CHANGELOG `## Unreleased` entry.
This document covers the remaining **Phase 2**: panel-level pan/zoom that frames the active comic
panel as narration plays, plus in-webview gesture detection (pinch-zoom) that feeds the existing
manual-mode pipeline.

## What Phase 1 already gives you (build on these, don't redo)

- A unified runtime "narration sync enabled" flag on each platform, gating audio→visual sync, that:
  - iOS: `EPUBReaderView.narrationSyncEnabled` + `setNarrationSyncEnabled(_:)`; emitted on the
    `dk.nota.flutter_readium/narration-sync` `EventStreamHandler` (registered in
    `FlutterReadiumPlugin.register`).
  - Android: `ReadiumReader.narrationSyncEnabled` + `setNarrationSyncEnabled()`; emitted via
    `events/NarrationSyncEventChannel.kt`.
  - Web: `ReadiumReader._narrationSyncEnabled` + `setNarrationSyncEnabled()`; emitted via
    `window.updateNarrationSync()` → `ReadiumBridge` → Dart `onNarrationSyncChanged`.
- Manual-mode entry on user navigation: native `enterManualModeIfNarrating`, reached from
  page-turns (`goForward`/`goBackward`) and from in-reader gestures via the Flutter
  `reader_widget.dart` `_onInteraction → ReadiumReaderChannel.notifyUserNavigation →` native
  `"notifyUserNavigation"` handler (iOS `EPUBReaderView.onMethodCall`, Android
  `ReadiumReaderWidget.onMethodCall`).
- Dart facade: `FlutterReadium.setNarrationSyncEnabled(bool)` + `Stream<bool> onNarrationSyncChanged`.

Phase 2's comic gesture detection must funnel into this same `narration-sync` channel.

## Critical architecture facts (verified)

- **Nota comics are EPUB + MediaOverlay**, rendered in the native EPUB **webview**, *not* the native
  DiViNa/CBZ `ImageNavigator`. They are driven by Media Overlay audio cues whose fragment ids are
  **comic-panel ids**.
- The comic helper bundle is **already injected** into every EPUB resource on native:
  - iOS `EPUBReaderView.initUserScripts` (~L677-700) + `setupUserScripts` (L203, the
    `WKUserContentController`).
  - Android `ReadiumExtensions.kt:172` (injects `assets/helpers/flutterReadiumTools.js` + `.css`).
  - The helper (`assets/_helper_scripts/src/NotaComicBookPage.ts`, `FlutterReadiumTools.ts`) already
    defines `window.gotoComicFrame(id, durationMs)` (`FlutterReadiumTools.ts:414`,
    `NotaComicBookPage.ts:88/:381`) and `window.isNotaComicBook()` (`NotaComicBookPage.ts:448`).
- Native **never calls `gotoComicFrame`** today. It only calls `window.flutterReadium.setSegmentDuration`
  (iOS `EPUBReaderView.swift:535`, Android `EpubNavigator.kt:180`) and other `window.flutterReadium.*`
  pulls. So comics do not pan on native — this is the core Phase 2 gap.
- `window.updateNarrationSync` is defined **only in the web bridge** (`ReadiumBridge.ts:60`); there is
  **no JS→native push channel** on iOS/Android (iOS only uses `addUserScript` for injection; Android
  uses Readium's decoration listener). Phase 2c adds it.
- **Web is the behavioral reference**: `ReadiumReader.ts:738-758` calls `window.gotoComicFrame` on each
  cue and skips the utterance highlight for comic frames; `ReadiumReader.ts:845` checks
  `isNotaComicBook`. `FlutterDivinaNavigator.ts` (`setAutoPan` L223, `panToRegion`, `_manuallyOverridden`)
  is the canvas-DiViNa manual-override model — reuse its *semantics*, not its code.

## Phase 2 tasks

### 2a. Native → JS: drive `gotoComicFrame` on each cue
In the native MediaOverlay visual-sync path (iOS `EPUBReaderView.syncToLocator`/`performSyncNavigation`;
Android the `syncVisualToLocator` EPUB branch / `EpubNavigator.syncToLocator`), when
`window.isNotaComicBook()` is true for the active resource:
- Call `window.gotoComicFrame(panelFragmentId, durationMs)` via `evaluateJavascript`
  (iOS `EPUBReaderView.swift:373`; Android `EpubNavigator.kt:365` / `EpubReaderFragment.kt:164`),
  instead of (or in addition to) the plain locator nav.
- **Skip the utterance highlight** for comic frames (mirror web).
- The panel fragment id + segment duration come from the cue (segment duration is already plumbed via
  `setSegmentDuration`). Honor the Phase 1 `narrationSyncEnabled` gate (don't pan in manual mode).

### 2b. Helper TS: gesture detection → `updateNarrationSync`
In `assets/_helper_scripts/src/NotaComicBookPage.ts`:
- Allow **manual pinch-zoom** of the current panel.
- Treat a manual pinch-zoom (and a swipe to a different page of the horizontal **triptych**) as the
  "user took control" gesture → call `window.updateNarrationSync?.(false)`. **Do not** implement free
  pan — pages live in a horizontally-swipeable triptych, so horizontal pan = page change, not panning.
- Call `window.updateNarrationSync?.(true)` on a narration-driven page turn or explicit re-sync.
- Reuse the override semantics proven in `FlutterDivinaNavigator.ts` (`_manuallyOverridden`,
  `setAutoPan`, `panToRegion`).
- After editing TS: `bin/typecheck`, then `bin/update_web_example` (never hand-edit built JS).

### 2c. JS → native push bridge (the genuinely new plumbing)
Make `window.updateNarrationSync(bool)` reach native and forward to the Phase 1 `narration-sync` channel:
- iOS: register a `WKScriptMessageHandler` (e.g. name `narrationSync`) on the EPUB navigator's
  `WKUserContentController` in `setupUserScripts` (`EPUBReaderView.swift:203`); helper posts via
  `window.webkit.messageHandlers.narrationSync.postMessage(bool)`; handler →
  `narrationSyncStreamHandler?.sendEvent(bool)` (and update `EPUBReaderView.narrationSyncEnabled`).
- Android: add a JS interface (or reuse a Readium webview hook) so the helper can post the bool; forward
  to `NarrationSyncEventChannel` / `ReadiumReader.setNarrationSyncEnabled`. Verify the mechanism
  survives Readium's webview setup.
- Keep `window.updateNarrationSync` as the **single JS entry point**; route web-vs-native via a thin
  platform shim set in the injected bootstrap (the same place the existing `isAndroid`/`isIos` flags
  are set). On web it already calls `ReadiumBridge`; on native it posts to the message handler.

### 2d. Re-sync for comics
Extend the Phase 1 `setNarrationSyncEnabled(true)` re-sync so that for comics it also: clears the JS
manual override (`evaluateJavascript` into the helper), re-pans to the current cue's panel, and resets
zoom. Single operation — **no retry burst** (explicitly forbidden).

### 2e. Region geometry
Guided-Navigation `imgref #xywh=pixel:x,y,w,h` is carried web-side via
`Locator.locations.otherLocations` (`mediaoverlay/syncNarration.ts`). For native EPUB-MO comics the
region is consumed **inside the JS helper** (it pans by panel-id fragment), so native likely does **not**
need to parse `xywh` into native models. Verify the helper resolves the panel from the fragment id
alone; add native region parsing only if it can't.

## Scope / non-goals

- Panel pan applies to **webview-rendered comics**: all iOS comic formats (iOS renders DiViNa/CBZ via the
  EPUB webview, `EPUBReaderView.swift:426`) and **Android EPUB-MO** comics.
- **Android image comics** (CBZ/DiViNa via `ComicNavigator`/`ImageNavigatorFragment`) stay **page-only** —
  no clean pan/zoom hook (documented at `ComicNavigator.kt:43` for B&W mode). Do not fake panel sync with
  view-tree hacks.
- No automatic seek/re-sync retry bursts.

## Verification

Use the `nota-comic` narrated EPUB-MO fixture in the example app:
1. Open comic, start narration → panels pan/zoom to the spoken panel; no yellow utterance highlight.
2. Pinch-zoom manually → `onNarrationSyncChanged(false)`, Re-sync button appears, audio continues.
3. Tap Re-sync → re-pans to the current panel + resets zoom; `onNarrationSyncChanged(true)`.
4. Swipe to another triptych page during narration → manual mode; Re-sync returns to the narrated page.
- `bin/typecheck` + `bin/update_web_example` (web TS); `bin/format && bin/analyze`; Android `ktlint --format`.
- iOS simulator + Android emulator smoke tests; ask the user to run device tests.

## Open items carried over from Phase 1

- **Android DiViNa page-sync (1c) needs a device check.** Phase 1 added `ReadiumReader.syncVisualToLocator`
  routing cue sync to `ComicNavigator.goToLocator`, but the 0.1.1 CHANGELOG already claims DiViNa
  page-synced audio on Android. Confirm whether the 1c routing is net-new or redundant; it was left out
  of the CHANGELOG pending that check.
- The native `goForward`/`goBackward` manual-mode triggers are partly redundant with `notifyUserNavigation`
  for in-reader taps (harmless/idempotent) but still required for app page-buttons.
