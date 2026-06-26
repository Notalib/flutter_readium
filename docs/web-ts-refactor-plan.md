# Web Platform (TypeScript) Structural Refactor

## Context

The web implementation lives in `flutter_readium/flutter_readium/web/_scripts/` and is built by webpack into `lib/helpers/readiumReader.js`. Today it centers on **`ReadiumReader.ts` — a 991-line god class** (`_ReadiumReader`, exported to `globalThis.ReadiumReader`) with ~30 public methods that mix publication lifecycle, visual navigation, EPUB preferences, decorations, audio playback, TTS, and media-overlay sync, and which holds *all* state. Navigators are created by free `initialize*()` functions returning bare upstream `@readium/navigator` objects, and `helpers.ts` (502 lines) is a grab-bag of manifest fetching, color conversion, decoration frame-comms, and iframe injection. Naming is inconsistent (`webPubPrefences.ts` typo; `Epub` vs `EPUB`).

By contrast the **native iOS/Android sides** use clean OO abstractions: a `ReadiumReaderView` protocol (visual nav), a `FlutterTimebasedNavigator` protocol with TTS/Audio/MediaOverlay strategy implementations, `Flutter*`-prefixed wrapper classes (prefix dodges upstream-Readium name collisions), dedicated `model/`/`preferences/`/`events/` dirs, and factory dispatch on publication type.

**Goal:** restructure the web TS to mirror the native architecture — better directory organization, consistent naming, and OO classes/interfaces — so the three platforms read alike and the web layer is maintainable. This is a structural refactor: logic moves largely verbatim; deep per-class cleanup is a later pass.

**Decisions (confirmed with user):**
- Source dir: rename **`web/_scripts/` → `web/src/`** (conventional name; also disambiguates from the separate `assets/_helper_scripts/` webview-helper bundle).
- Wrapper class naming: **`Flutter*` prefix** (mirrors native; renames `WebTTSEngine` → `FlutterTTSNavigator`).
- Scope: **full restructure** — including collapsing `_ReadiumReader` into a thin facade.
- Delivery: **single PR, composed of small atomic commits** (one per migration step below), build + tests green at each commit.

**Hard invariant:** the Dart↔JS contract must not change. The `globalThis.ReadiumReader` method names/signatures (`openPublication`, `goTo`, `setEPUBPreferences`, `ttsEnable`, …) and the `window.*` callback names/JSON shapes (`updateTextLocator`, `updateReaderStatus`, `updateTimebasedPlayerState`, `onTextSelectedCallback`, `onErrorCallback`) stay byte-identical. No changes to Dart `js_interop` (`lib/src/js_publication_channel.dart`) are required.

## Target directory tree (`web/src/`)

```
index.ts                       # NEW webpack entry: import style.css, build facade, assign globalThis.ReadiumReader, install bridge
ReadiumReader.ts               # SHRUNKEN facade/dispatcher (~150-200 lines)
style.css                      # unchanged

bridge/
  ReadiumBridge.ts             # ONLY code allowed to touch window.* emit callbacks
  window.d.ts                  # was flutter.d.ts

publication/
  PublicationManager.ts        # publication lifecycle + static _publications cache + fetchManifest glue

navigators/
  VisualNavigator.ts           # INTERFACE (mirrors ReadiumReaderView)
  TimebasedNavigator.ts        # INTERFACE (mirrors FlutterTimebasedNavigator)
  locatorEnrich.ts             # shared enrichWithTotalProgression/tocHref/flattenToc (EPUB+WebPub both use)
  FlutterEpubNavigator.ts      # was Epub/epubNavigator.ts (free fn -> class impl VisualNavigator)
  FlutterWebPubNavigator.ts    # was WebPub/webpubNavigator.ts
  FlutterAudioNavigator.ts     # was Audio/audioNavigator.ts (impl TimebasedNavigator)
  FlutterTTSNavigator.ts       # was TTS/ttsNavigator.ts (WebTTSEngine renamed, impl TimebasedNavigator)
  FlutterMediaOverlayNavigator.ts # was Audio/mediaOverlayNavigator.ts (owns sync + comic cue logic)

mediaoverlay/
  syncNarration.ts             # was Audio/syncNarration.ts
  guidedNavigation.ts          # was Audio/guidedNavigation.ts

decorations/
  DecorationController.ts      # applyDecorations/setDecorationStyle/_subgroupFor + style/group state (from god class)
  decorationOverrides.ts       # from helpers.ts: sendDecorate, navIframeWindows, registerPendingDecorationGroup,
                               #   injectDecorationOverrides, UNDERLINE_GROUP_SUFFIX, highlightSelection

preferences/
  FlutterEpubPreferences.ts    # was Epub/epubPreferences.ts (+ convertVerticalScroll/textAlignFromJson/normalizeTypes)
  FlutterWebPubPreferences.ts  # was WebPub/webPubPrefences.ts  <- TYPO FIXED
  FlutterAudioPreferences.ts   # NEW: extracted setAudioPreferences mapping (from god class) + preferencesFromString (from audioNav)
  FlutterTTSPreferences.ts     # was TTS/ttsPreferences.ts

model/
  ReadiumReaderStatus.ts       # was enums.ts (room for typed ReadiumTimebasedState later)

utils/
  ReadiumPluginLogger.ts       # was logger.ts
  ReadiumExtensions.ts         # was extensions/ReadiumPublication.ts + helpers' mediaTypes + findLinkByHref
  colors.ts                    # was helpers' dartColorToCss
  manifest.ts                  # was helpers' fetchManifest
  iframeInjection.ts           # was helpers' injectFlutterReadiumHelperScripts + asset cache
  Peripherals.ts               # was peripherals.ts

__tests__/                     # import paths updated to final locations (re-export shims bridge the transition)
```

`helpers.ts` is fully dissolved across the above.

## Interfaces to introduce

**`VisualNavigator`** (mirrors iOS `ReadiumReaderView`) — implemented by `FlutterEpubNavigator`, `FlutterWebPubNavigator`:
- `underlying` (escape hatch for decoration frame-comms), `currentLocator`, `positions` (EPUB has them; WebPub `[]`)
- `goRight/goLeft/goForward/goBackward`, `goToLink(link, animated)`, `goToLocator(locator, animated)`, `goToProgression(p)`, `destroy()`
- The `initialize*AndPeripherals` free functions become static `create(...)` factories returning the wrapper (the `setNav`/`setPositions` callbacks disappear).

**`TimebasedNavigator`** (mirrors iOS `FlutterTimebasedNavigator`) — implemented by `FlutterTTSNavigator`, `FlutterAudioNavigator`, `FlutterMediaOverlayNavigator` (strategy pattern):
- `play(locator?)`, `pause()`, `resume()`, `stop()`, `next()`, `previous()`, `seekBy(s)`, `goToProgression(p)`, `goToLocator(locator)`, `destroy()`
- Collapses the facade's repeated `if (this._ttsEngine) … else if (this._audioNav) …` branching into "dispatch to the single active `timebasedNav`."

## Facade shape after collapse

```
class _ReadiumReader {
  private bridge: ReadiumBridge;
  private pubManager: PublicationManager;
  private visualNav?: VisualNavigator;
  private timebasedNav?: TimebasedNavigator;  // TTS | Audio | MediaOverlay (the active one)
  private decorations: DecorationController;
}
```
Public method names/signatures unchanged. Method → new home (representative; full map in commits):
- `getPublication` → `pubManager`; `openPublication`/`closePublication` → facade orchestrates collaborators
- `goRight/Left/Forward/Backward`, `goToProgression(visual)` → `visualNav`
- `goTo` → facade keeps the route decision (TTS vs MediaOverlay vs audiobook vs visual), delegates each branch; text↔audio mapping moves into `FlutterMediaOverlayNavigator.goToLocator`
- `applyDecorations/setDecorationStyle/_subgroupFor` → `DecorationController`
- `play/pause/resume/stop/next/previous/seekBy`, `audioEnable`, `ttsEnable`, `ttsSetVoice/ttsSetPreferences` → `timebasedNav`
- `setAudioPreferences`/`setEPUBPreferences` → `preferences/*` modules applied to the relevant nav
- `_syncVisualToMediaOverlayLocator`/`_callGotoComicFrame` + `_isComicBook`/`_lastMediaOverlayLocatorKey` → `FlutterMediaOverlayNavigator`
- `disableSynchronization` stays facade-side (cross-cutting plugin state, passed at enable-time)

## Bridge (centralized `window.*`)

`bridge/ReadiumBridge.ts` is the only module touching `window.*`. Typed methods wrap each callback with **identical names/JSON shapes**: `emitReaderStatus`, `emitTextLocator` (uses `JSON.stringify(locator.serialize())` per project convention), `emitTimebasedState`, `emitTextSelected`, `emitError`. Navigators receive the bridge (or the specific emit callbacks) by injection rather than reaching `window` directly. The 200ms EPUB text-locator debounce is preserved (stays in `FlutterEpubNavigator` calling `bridge.emitTextLocator`).

## Migration ordering (each = one atomic commit; build + jest + tsc green at every step)

Principle: **move/rename first behind re-export shims, refactor internals last.**

**Phase 0 — rename source dir (`git mv`, no code change)**
0. `git mv web/_scripts web/src`. Update path references: `flutter_readium/package.json` (4 script paths: `build:dev`, `build`, `typecheck`, `test`), `web/src/webpack.config.js` (entry comment — output is `__dirname`-relative so unchanged), `.vscode/{launch,settings,tasks}.json`, `.github/instructions/typescript.instructions.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `docs/architecture.md`, `docs/parity/*`, and the `bin/typecheck` comment. `bin/` scripts invoke `npm run`, so no functional change there. Verify with `bin/typecheck` + `npx jest` + `bin/build_js` (bundle still emits to `lib/helpers/readiumReader.js`). All subsequent steps operate under `web/src/`.

**Phase A — non-behavioral moves**
1. Create `utils/`, `model/`; move logger→`ReadiumPluginLogger.ts`, peripherals→`Peripherals.ts`, `extensions/ReadiumPublication.ts`→`ReadiumExtensions.ts`, enums→`model/ReadiumReaderStatus.ts`. Re-export shims at old paths.
2. Split `helpers.ts` → `decorations/decorationOverrides.ts`, `utils/colors.ts`, `utils/manifest.ts`, `utils/iframeInjection.ts`, fold `mediaTypes`/`findLinkByHref` into `ReadiumExtensions.ts`. Keep `helpers.ts` as a re-export barrel.
3. Fix typo/casing: preferences files → `preferences/FlutterEpubPreferences.ts`, `FlutterWebPubPreferences.ts`, `FlutterTTSPreferences.ts`. Shims at old paths.

**Phase B — navigators to classes (verbatim logic)**
4. `FlutterEpubNavigator` + shared `navigators/locatorEnrich.ts` (move `enrichWithTotalProgression`). Old free fn becomes thin wrapper.
5. `FlutterWebPubNavigator` (imports enrich from shared module — removes the cross-`Epub` import).
6. `FlutterAudioNavigator` (preserve `export const __testing__`; re-export for tests).
7. `FlutterTTSNavigator` (rename `WebTTSEngine`).
8. `FlutterMediaOverlayNavigator` (preserve `__testing__`; move comic + cue-sync logic in from god class).

**Phase C — extract facade collaborators**
9. `bridge/ReadiumBridge.ts` + `window.d.ts`; route all `window.*` through it.
10. `publication/PublicationManager.ts`.
11. `decorations/DecorationController.ts`.
12. `preferences/FlutterAudioPreferences.ts`.

**Phase D — collapse + re-point entry**
13. Rewrite `_ReadiumReader` as the thin dispatcher delegating to collaborators + active navigators. Diff its public-method list against the original to confirm the contract is intact.
14. Add `index.ts` entry; update `webpack.config.js` `entry: ReadiumReader.ts → index.ts`. Output path `../../lib/helpers/readiumReader.js` unchanged.
15. Delete all re-export shims; update remaining `__tests__` imports to final paths; remove `helpers.ts` barrel.

**Imports/paths that must be touched (only these):** dir-rename path references in step 0 (package.json, .vscode, docs, instructions); `__tests__/*.test.ts` import paths (deferred via shims until each phase; preserve `__testing__` and named exports `enrichWithTotalProgression`/`dartColorToCss`); `webpack.config.js` entry (step 14). **Dart `js_interop`: no changes.**

## Critical files (paths shown post-rename, i.e. under `web/src/`)

- `web/src/ReadiumReader.ts` — the god class to dissolve
- `web/src/helpers.ts` — the grab-bag to split
- `web/src/Audio/{audioNavigator,mediaOverlayNavigator,syncNarration,guidedNavigation}.ts`
- `web/src/{Epub,WebPub,TTS}/*` — navigators + preferences to reclass/rename
- `web/src/webpack.config.js` — entry path (step 14 only)
- `web/src/__tests__/*.test.ts` — import-path updates
- `flutter_readium/package.json`, `.vscode/*` — dir-rename path references (step 0)

## Verification (per commit + final)

Run from repo root unless noted:
- `bin/typecheck` — `tsc --noEmit` over web TS (run after any TS edit).
- **Unit tests (Jest):** `npm test` — the **7** existing suites (`audioNavigator`, `epubNavigator`, `guidedNavigation`, `mediaOverlayNavigator`, `syncNarration`, `closePublication`, `helpers`) must stay green at **every** commit. As files move, update each test's import paths (e.g. `helpers.test.ts` imports `dartColorToCss` from `../helpers`; `closePublication.test.ts` and the navigator tests import the modules/`__testing__` exports directly). Re-export shims keep them green until their owning step; final step re-points them to canonical paths. **Do not weaken or skip a test to make it pass** — a failing unit test signals a real regression.
- **Integration tests (Dart):** `example/integration_test/` (`plugin_integration_test.dart` with `test_fixtures_web.dart`) exercise the web platform end-to-end and are the strongest contract-regression gate. Because the Dart↔JS contract is preserved, **these must pass with their source unchanged** — if a fixture or assertion needs editing to pass, treat it as evidence the contract drifted and fix the TS, not the test. Run them on the web target (`flutter test integration_test` / driver) after the facade collapse (step 13) and again at the end (step 15).
- `bin/build_js` then `bin/update_web_example` — confirm `lib/helpers/readiumReader.js` regenerates and is copied into `example/web/`.
- `bin/format` && `bin/analyze` — Dart side unchanged but required pre-PR (checks all packages).
- **End-to-end smoke (final, mandatory for this behavioral refactor):** run the example app on web/Chrome, then exercise each affected path — open an EPUB (paginated + scroll), navigate (arrows/goTo/progression), apply a highlight/underline decoration, enable TTS and play/pause/next, play a media-overlay/sync-narration title and confirm visual sync + comic-frame handling, open a plain audiobook and seek. Confirm via the reader UI and logs that `updateTextLocator`/`updateTimebasedPlayerState`/`updateReaderStatus` still fire with unchanged shapes. (Per project memory: do not delegate Flutter-web in-browser verification to a sub-agent — verify manually.)
- **Contract check:** diff the final facade's public method names against the original `_ReadiumReader` and the `window.*` callback names to prove the Dart↔JS contract is byte-identical.

## Execution

- **Plan persisted in repo** at `docs/web-ts-refactor-plan.md` (committed as the first commit on the feature branch) so it travels with the PR and reviewers can follow the step map.
- Implementation proceeds **sequentially**, one atomic commit per numbered step (0 → 15); each step runs only after the previous step's verification gate passes. Steps are dependent — re-export shims/barrels are removed only in step 15, so steps must not be reordered or parallelized.

## CHANGELOG

This is an internal restructure with no consumer-visible behavior change, so no CHANGELOG entry is warranted (Keep-a-Changelog test fails). Note the rationale in the PR description instead.
