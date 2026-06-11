# Fix comic-book media-overlay on Web

> **✅ Implemented** on `feat/web-feature-parity` (commit `e16e8dd8`). Comic panels pan/zoom on web via the injected helper bundle, and the spurious yellow highlight is suppressed. Retained for reference.

## Problem
Special "Nota" comic-book media-overlay EPUBs misbehave on **Web only**:
1. A large **yellow highlight** rectangle is drawn over the comic frame (unwanted).
2. **No zoom/pan** of the comic panels as audio plays — the frame just shows
   the whole page, with a yellow box where the panel `div.area` sits.

## Root cause
The comic pan/zoom logic lives in the **helper-scripts bundle**
(`flutter_readium/assets/_helper_scripts/src/NotaComicBookPage.ts` +
`ComicBookCalc.ts`), built to `assets/helpers/flutterReadiumTools.js`.

- On **native** (iOS/Android) this bundle is injected **into the EPUB webview**.
  It creates a fixed, full-viewport overlay (`z-index:9999`) that pans/zooms a
  cloned panel image, hides the `div.area` elements (so no yellow box), and
  exposes `window.gotoComicFrame(id, duration)` + overrides
  `window.readium.scrollToId`.
- On **Web** the navigator renders each EPUB resource in a same-origin
  `.readium-navigator-iframe`, but **the comic helper is never injected** into
  that iframe. So there is no overlay, the `div.area` panels stay visible, and
  the media-overlay navigator's utterance highlight paints a yellow rectangle
  over the panel.

The web media-overlay path (`ReadiumReader._syncVisualToMediaOverlayLocator`)
treats a comic frame like any text utterance: `nav.go(locator)` + apply a
`media_overlay_utterance` highlight decoration.

## Approach (mirror native)
Inject the existing comic helper into the web navigator iframe, and special-case
comics in the web media-overlay navigator so they pan/zoom instead of getting a
highlight.

### Phase 1 — Inject the SAME helper scripts as native into web EPUB iframes
**Decision (confirmed): inject the full prebuilt bundle, exactly mirroring native.**

Native injects the following into every EPUB resource `<head>` (iOS
`EPUBReaderView.initUserScripts`, Android `ReadiumExtensions.kt`):
1. `assets/helpers/flutterReadiumTools.js` — the full helper bundle (comic
   pan/zoom **and** `FlutterReadiumTools`: viewport/page-info/tables).
2. `assets/helpers/flutterReadiumTools.css` — helper styles (comic overlay,
   `div.area` hiding, B/W comic mode, responsive tables).
3. `const isAndroid = …; const isIos = …;` OS-detection flags.
4. `window.readiumTocIDs = [...]` — flattened ToC fragment ids.

Mirror all four on web. In `Epub/epubNavigator.ts` `frameLoaded` (same place
`injectDecorationOverrides` already runs against `frameManager.window`), inject
into that same-origin iframe **once** (dataset-flag guard):
- A small inline bootstrap `<script>` setting `const isAndroid = false; const
  isIos = false; window.readiumTocIDs = <flatToc ids>;` (web ⇒ both flags false;
  reuse the `flatToc` we already compute).
- The CSS: `fetch()` the Flutter web asset
  `assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.css` and
  append as a `<style>`.
- The JS: `fetch()` `…/assets/helpers/flutterReadiumTools.js` and inject as an
  inline `<script>` (after the bootstrap so `readiumTocIDs`/flags exist first).
- No helper-build/copy pipeline change; assets are already bundled via
  `pubspec.yaml assets: assets/helpers/`. Same-origin iframe DOM/script
  injection already proven by `injectDecorationOverrides`.
- This makes the iframe self-initialize exactly like native: comic overlay
  created, `div.area` hidden (kills the yellow box), `window.gotoComicFrame` +
  `window.isNotaComicBook` + `window.flutterReadium` exposed.
- Add a helper in `helpers.ts` (e.g. `injectFlutterReadiumHelperScripts(wnd,
  tocIds)`), fetching the two assets once and caching the text.

### Phase 2 — Special-case comics in the media-overlay navigator
In `ReadiumReader._syncVisualToMediaOverlayLocator`:
- After navigating to the comic resource, detect a comic frame:
  query the active `.readium-navigator-iframe` and check
  `iframeWindow.isNotaComicBook?.()`.
- If it is a comic:
  - Call `iframeWindow.gotoComicFrame(fragmentId, durationMs)` with the cue's
    fragment id and segment duration (so panning timing matches the audio).
  - **Skip** the `media_overlay_utterance` highlight decoration entirely.
- Otherwise keep the existing highlight behaviour unchanged.
- Plumb segment duration through: extend the `onTextLocatorChanged` callback (or
  compute in the mapper) so the cue duration `audioEnd - audioStart` (ms) reaches
  `_syncVisualToMediaOverlayLocator`. Falls back to a default when unavailable.

### Phase 3 — Build, verify, changelog
- `bin/typecheck` (web TS), then `bin/build_js` + `bin/update_web_example`.
- Smoke-test the comic media-overlay book in the example app on web (Chrome):
  confirm panels zoom/pan and the yellow box is gone.
- `bin/format && bin/analyze`.
- Add a `## Unreleased` `fix(web):` entry to `CHANGELOG.md`.

## Key files
- `flutter_readium/web/src/Epub/epubNavigator.ts` — inject helper in `frameLoaded`.
- `flutter_readium/web/src/helpers.ts` — `injectComicBookHelper` util.
- `flutter_readium/web/src/ReadiumReader.ts` — comic special-case + duration plumbing.
- `flutter_readium/web/src/Audio/mediaOverlayNavigator.ts` — pass cue duration to callback (if needed).
- `CHANGELOG.md`.

## Decision (confirmed)
Inject the **same prebuilt helper bundle + CSS + bootstrap** as native does —
single source of truth, exact native parity (Option A). No porting/forking of
comic logic into the web build; no animejs added to the web bundle.
