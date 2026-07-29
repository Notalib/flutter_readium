# Native DiViNa Narration Sync Handoff

> **✅ Phase 1 implemented.** Narration sync state, manual mode, Re-sync, and the unified
> `FlutterReadium.setNarrationSyncEnabled(bool)` / `onNarrationSyncChanged` surface are landed on
> Dart, iOS, Android, and Web. This file is retained as the implemented reference for that slice.
> Remaining native comic cue framing work now lives in
> [todo/native-comic-panel-pan-handoff.md](todo/native-comic-panel-pan-handoff.md).

## What landed

The original brief was generalized from comic-only auto-pan into a shared narration-sync model
for Media Overlay and TTS:

- `FlutterReadium.onNarrationSyncChanged` reports whether the reader is still following narration.
- `FlutterReadium.setNarrationSyncEnabled(true)` performs the explicit Re-sync action.
- `EPUBPreferences.disableSynchronization` remains as a deprecated seed for the runtime flag.
- Manual user navigation while narration is active enters manual mode instead of force-seeking the
  visual reader back to the current cue.
- Web, iOS, and Android now share the same consumer-visible manual-mode semantics.

## Source-of-truth behavior

The landed behavior is documented and exercised across these areas:

- `flutter_readium/lib/flutter_readium.dart`
- `flutter_readium/lib/src/flutter_readium_web.dart`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/reader/EPUBReaderView+Navigation.swift`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReader.kt`
- `flutter_readium/web/src/ReadiumReader.ts`
- `flutter_readium/assets/_helper_scripts/src/NotaComicBookPage.ts`
- `flutter_readium/CHANGELOG.md`

## What was intentionally deferred

The original plan also covered native comic-specific cue framing beyond page-following:

- panel pan/zoom for DiViNa / Guided Navigation cues on iOS and Android
- transport of guided-navigation panel geometry (`imgref#xywh=...`) into native visual sync
- native visual framing parity with the existing web comic helper

That remaining work is still open and has been split into a dedicated actionable plan:
[todo/native-comic-panel-pan-handoff.md](todo/native-comic-panel-pan-handoff.md).

## Why this split exists

The old single file mixed two different states:

- already-landed narration sync infrastructure
- still-open native comic panel framing work

Keeping the implemented slice here avoids losing the rationale behind the unified manual-mode API,
while the follow-up plan can stay narrowly focused on the remaining native comic behavior.
