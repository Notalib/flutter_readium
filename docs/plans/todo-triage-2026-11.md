# TODO triage, 2026-11

Snapshot of every `TODO` / `FIXME` marker in the repo and the plan documents, classified by what to do with it. Produced by a read-only spike on 2026-11-09; GitHub was unreachable during the spike, so open issues and PRs were not cross-checked.

Classes: **fix-now** (done in the same change), **file-issue** (grouped into G1-G9 below, not one issue per marker), **upstream** (the real fix belongs in a Readium toolkit), **delete** (not a task: stub, rationale or template line).

Counts: fix-now 3, file-issue 35, upstream 10, delete 6. The spike table omitted the three `FlutterDecorationPreferences.kt` markers that G4 refers to; they are listed here.

Paths are shortened: Android paths are under `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/`, iOS under `flutter_readium/ios/flutter_readium/Sources/flutter_readium/`, `platform_interface/` is `flutter_readium_platform_interface/lib/src/`, and Dart, web and example paths start at `flutter_readium/`.

### Dart

| Location | Marker | Class | Reason |
|---|---|---|---|
| `reader_widget.dart:197` | presumes btt / vertical progression never used | file-issue G3 | Hidden assumption; needs a decision on btt support. |
| `reader_widget.dart:219` | presumes one semantic label per toggle | file-issue G3 | Accessibility-label assumption; low priority. |
| `reader_widget.dart:354` | `TODO — Implement ReadiumReaderWidget on ${os}` (user-visible) | fix-now | Unsupported-platform message. Done in this branch. |
| `reader_widget.dart:431` | remove workaround once Readium fixes the underlying issue | upstream | Depends on an upstream fix; toolkit not yet identified. |
| `reader_widget.dart:458` | `isAudioBookWithText: false`, "we don't know atm" | file-issue G3 | Hardcoded; needs a real source. |
| `reader_widget.dart:522` | handling "not necessarily how it should be handled" | file-issue G3 | Vague; needs a concrete case. |
| `platform_interface/.../readium_color_extension.dart:8` | opacity not supported: our bug or toolkit limit? | file-issue G9 | Open question; confirm against swift-toolkit before filing upstream. |
| `platform_interface/.../utils/href.dart:17` | does NOT resolve `../` | file-issue G7 | Real bug; the fix needs edge-case tests. |
| `platform_interface/.../epub/publication_extension.dart:25` | localise `"Page x"` title | file-issue G7 | Needs an i18n decision (who supplies strings). |
| `platform_interface/.../publication/format.dart:43` | FIXME video MIME types? | file-issue G7 | Needs a list of supported video types. |
| `platform_interface/.../publication/format.dart:55` | FIXME video file extensions? | file-issue G7 | Same as line 43. |
| `platform_interface/test/flutter_readium_platform_interface_test.dart:36` | `return 'TODO';` in test stub | delete | Stub return value, not a task marker. Done in this branch. |
| `example/lib/widgets/text_settings.widget.dart:389` | web reader has no CSS-injection infrastructure yet | file-issue G8 | Web feature gap; needs a scope decision. |
| `example/lib/state/publication_bloc.dart:173` | check if audio is enabled, not just present | file-issue G9 | Example-app logic; no requirement stated. |
| `example/lib/pages/player.page.dart:320` | implement `restoreState` | file-issue G9 | Example-app gap; keep or drop the feature. |

### Android

| Location | Marker | Class | Reason |
|---|---|---|---|
| `FlutterReadiumPlugin.kt:46` | "Remove this, just for debugging." | fix-now | Debug asset listing; nothing depended on it. Done in this branch. |
| `PluginMediaService.kt:318` | submit on plugin audio-locator stream? | file-issue G1 | Design question on event emission. |
| `PluginMediaService.kt:374` | restoration from a stale notification | file-issue G1 | Real gap; needs a reproduction. |
| `events/ReadiumReaderStatusEventChannel.kt:32` | "no way to emit this right now" | file-issue G9 | Missing event; add it or drop the stub. |
| `ReadiumReaderWidget.kt:405` | "To be safe we're doing everything on Main thread" | delete | Rationale, not a task. Reworded in this branch. |
| `ReadiumExtensions.kt:888` | remove once kotlin-toolkit's ImageParser parses ComicInfo.xml | upstream | kotlin-toolkit; upstream issue existence unchecked. |
| `fragments/EpubReaderFragment.kt:868` | temporary image-tap solution until kotlin-toolkit supports it | upstream | kotlin-toolkit; unchecked. |
| `fragments/EpubReaderFragment.kt:872` | drop once kotlin-toolkit reports same-document link taps | upstream | kotlin-toolkit; unchecked. |
| `FlutterAudioPreferences.kt:91` | "Not sure if this is correct" | file-issue G1 | Verify against the toolkit's audio settings. |
| `models/FlutterMediaOverlay.kt:214` | FIXME: `skipToAudioLocator` time uses audioStart, not progression | file-issue G1 | Concrete bug; reproduce with a media-overlay fixture first. |
| `navigators/TTSNavigator.kt:583` | TTS-specific error handling | file-issue G1 | Scope unclear. |
| `navigators/AudiobookNavigator.kt:284` | better error handling when factory is null | file-issue G1 | Null-factory case can fail silently. |
| `navigators/AudiobookNavigator.kt:472` | do we need to check if already playing? | file-issue G1 | Investigate; likely a guard. |
| `ReadiumReader.kt:151` | custom headers and auth for content files | file-issue G6 | Feature; needs an API decision. |
| `ReadiumReader.kt:417` | "Handle this somehow" | file-issue G6 | Vague; name the failing case. |
| `ReadiumReader.kt:692` | should client pass mediaType to assetRetriever? | file-issue G6 | API design question. |
| `navigators/ComicNavigator.kt:151` | ask Readium for ImageNavigatorFragment | upstream | kotlin-toolkit; unchecked. |
| `navigators/ComicNavigator.kt:240` | replace with real flag once kotlin-toolkit exposes paging/zoom | upstream | kotlin-toolkit; unchecked. |
| `FlutterDecorationPreferences.kt:8-10` | decide defaults; configurable at build time?; richer styles? | file-issue G4 | Defaults chosen ad hoc. Missing from the spike table, found while resolving G4. |
| `src/test/.../FlutterReadiumPluginTest.kt:17` | `@Ignore("TODO: flesh out plugin-level method call tests")` | file-issue G9 | Test gap; dead weight until filled. |

### iOS

| Location | Marker | Class | Reason |
|---|---|---|---|
| `navigator/NowPlayingInfoUpdater.swift:45` | limit cover size? | file-issue G2 | Perf question; no evidence of a problem. |
| `navigator/NowPlayingInfoUpdater.swift:229` | should these skip a full track? | file-issue G2 | Behaviour decision. |
| `navigator/NowPlayingInfoUpdater.swift:237` | same as 229 | file-issue G2 | Same decision. |
| `navigator/FlutterAudioNavigator.swift:489` | LCP errors ignored until LCP is supported | delete | LCP is out of scope (README). Reworded in this branch. |
| `navigator/FlutterAudioNavigator.swift:959` | should be handled by the Readium navigator | upstream | swift-toolkit; unchecked. |
| `reader/EPUBReaderView.swift:171` | PoC for custom editing actions; configure from Flutter | file-issue G8 | Feature decision. |
| `reader/EPUBReaderView.swift:364` | send resource-load error this way? | file-issue G8 | Error-contract question. |
| `reader/EPUBReaderView.swift:438` | see TODO in swift-toolkit `HTMLResourceContentIterator` | upstream | Pointer to a swift-toolkit TODO; unchecked. |
| `reader/EPUBReaderView+JSBridge.swift:181` | report upstream: `spreadViewDidLoad` re-injection | upstream | swift-toolkit; good candidate for an upstream issue. |
| `FlutterReadiumPlugin.swift:309` | language arg ignored on iOS for now | file-issue G5 | Parity gap with Android search. |
| `FlutterReadiumPlugin.swift:599` | physical page numbers for search results? | file-issue G5 | Feature decision. |

### Web and assets

| Location | Marker | Class | Reason |
|---|---|---|---|
| `web/src/utils/Peripherals.ts:53` | skip key handling when typing in input/textarea | fix-now | Done in this branch (guard plus Jest test). |
| `web/src/preferences/FlutterEpubPreferences.ts:277` | are these the default preferences we want? | file-issue G4 | Product decision on defaults. |
| `assets/_helper_scripts/src/FlutterReadiumTools.scss:21` | temporary fix for readium-css issue #129 | upstream | readium-css, not one of the three toolkits; check whether #129 is closed. |

### Example template markers

| Location | Marker | Class | Reason |
|---|---|---|---|
| `example/android/app/build.gradle.kts:25` | application ID placeholder | delete | Flutter template line. Deleted in this branch. |
| `example/android/app/build.gradle.kts:38` | release signing placeholder | delete | Flutter template line. Deleted in this branch. |
| `example/ios/Runner/AppDelegate.swift:20` | "Test if this works" | delete | Left in place: verify the custom action path by hand first. |

## Proposed GitHub issues

Not filed yet; the orchestrator files these after review.

### G1: `Android audio error handling and restore gaps`

Several Android audio paths lack error handling or have unverified behaviour (`PluginMediaService` 318/374, `FlutterAudioPreferences` 91, `TTSNavigator` 583, `AudiobookNavigator` 284/472). The `skipToAudioLocator` time bug in `FlutterMediaOverlay.kt:214` is the concrete one; reproduce it with a media-overlay fixture first.

### G2: `Now Playing: cover size and skip-track behaviour`

The Now Playing cover image size is unbounded, and skip may need to move by a whole track (`NowPlayingInfoUpdater.swift` 45/229/237). Decide the skip behaviour, then cap the cover.

### G3: `Remove hardcoded assumptions in ReadiumReaderWidget`

`reader_widget.dart` assumes btt progression is unused, a single semantic label per toggle, and `isAudioBookWithText: false` (lines 197/219/458/522). Read these from the publication or document why they are fixed.

### G4: `Decide default decoration and EPUB preference values`

Defaults in `FlutterDecorationPreferences.kt:8-10` and `FlutterEpubPreferences.ts:277` were chosen ad hoc and are marked undecided. Settle them and decide whether they are configurable at build time.

### G5: `iOS search: language option and page numbers`

iOS ignores the language argument that Android accepts (`FlutterReadiumPlugin.swift:309`). Search results also lack physical page numbers (line 599).

### G6: `Android content loading: headers, errors, mediaType`

Custom headers and auth are not forwarded to content requests (`ReadiumReader.kt:151`), and an error path says "handle this somehow" (417). Asset retrieval does not take a client `mediaType` (692).

### G7: `Href ../ resolution and format MIME gaps`

`href.dart:17` does not resolve `../` segments. Video MIME types and extensions in `format.dart` are incomplete, and the `"Page x"` title is not localised.

### G8: `iOS EPUB reader: editing actions and load errors`

The editing-action PoC in `EPUBReaderView.swift:171` is not configurable from Flutter, and the resource-load error contract (364) is unclear. The web reader also lacks CSS injection for the example app's text settings.

### G9: `Opacity, status events and example-app restore gaps`

Opacity may be unsupported by the toolkit (`readium_color_extension.dart:8`), and the Android status event channel has no emitter. The plugin-level Android test is `@Ignore`d, and the example app does not restore state or check that audio is enabled.

## Upstream candidates

Search the upstream trackers for an existing issue before filing.

### swift-toolkit: `Decorations duplicated when spreadViewDidLoad replays a group`

After a ToC jump during TTS, `spreadViewDidLoad` re-injects decorations without clearing the group, so an id gets two DOM elements and `DecorationChange` removes only the first. `clear()` the group before replaying, or let `DecorationChange` remove all elements for an id (`EPUBReaderView+JSBridge.swift:181`).

### kotlin-toolkit: `ImageParser should parse ComicInfo.xml`

`ImageParser` emits only `conformsTo = [DIVINA]`, so CBZ titles are blank on Android while iOS shows them. The plugin reads `ComicInfo.xml` itself (`ReadiumExtensions.kt:888`) and the marker still has a `<TBD>` tracking link to fill in.

### kotlin-toolkit: `Image navigator: insets and paging/zoom gesture coordination`

`ImageNavigatorFragment` has no equivalent of `EpubNavigatorFragment.Configuration.shouldApplyInsetsPadding`, and exposes no paging/zoom gesture coordination. The plugin works around both reflectively (`ComicNavigator.kt` 151/240).
