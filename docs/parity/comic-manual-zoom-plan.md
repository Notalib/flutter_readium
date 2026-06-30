# Comic manual zoom/pan — implementation plan (A′ primary, A fallback)

## Goal

Let the user pinch-zoom (and pan) a Nota MO-comic panel while narration is playing.
The first pinch desyncs narration (manual mode); tapping **Re-sync** restores the
auto pan/zoom to the current narrated panel. Must not break the triptych pager's
single-finger horizontal page-swipe.

## Rendering model (what we're working inside)

- `NotaComicBook` (singleton) owns a `position: fixed`, full-viewport overlay
  `div.nota-comicbook-page-container` (`100vw×100vh`, `z-index:9999`). While a comic
  page is active, `body { overflow: hidden }`.
- The active `NotaComicBookPage` clones the comic `<img>` into that container
  (`position: absolute`) and animates its `top/left/width/height` (Web Animations
  API) to pan/zoom across panels ("Ken Burns"). Exactly one clone `<img>` exists in
  the container at a time: `container.querySelector('img')`.
- Narration drives this via `gotoComicFrame(id, duration)` → `scrollToId` override.
- Manual zoom is rebuilt **inside this overlay** — we do NOT use the webview's native
  pinch-zoom (Readium injects a non-scalable viewport for these reflowable EPUBs, and
  it can't be animated per cue anyway).

## Current state (post-revert, starting point)

- `NotaComicBook.#initGestureDetection()` is **detection-only**: a 2-finger
  `touchmove` fires `window.updateNarrationSync?.(false)` once per gesture.
- `clearManualOverride()` just resets `#manualOverrideActive`.
- Desync bridge works: JS `updateNarrationSync(false)` → native `setNarrationSyncEnabled(false)`;
  Re-sync (native) → replays the deferred locator + calls `clearManualOverride()`.
- **Probe to remove** (both plans): iOS `EPUBReaderView.resetWebViewZoom()` and its call
  in `setNarrationSyncEnabled` — zoom is JS-owned now, native zoom reset is unused.

---

## Shared groundwork (do first, both plans)

1. **Remove the iOS native-zoom probe**: delete `resetWebViewZoom()` and its call site in
   `EPUBReaderView.setNarrationSyncEnabled`. Keep the unconditional `clearManualOverride()`
   JS call and the deferred-locator replay (those are correct and platform-agnostic).
2. **Freeze helper on `NotaComicBookPage`**: add a method to pause the running animation and
   commit the currently-rendered frame to inline styles, returning it:
   ```ts
   public freezeAtCurrentFrame(): { top: number; left: number; width: number; height: number } {
     const img = this.#container.querySelector<HTMLImageElement>('img');
     // read live values (works mid-animation), cancel animation, write back as inline styles
     const cs = img ? getComputedStyle(img) : null;
     const frame = { top: parseFloat(cs?.top ?? '0'), left: ..., width: ..., height: ... };
     this.#animation?.cancel(); this.#animation = undefined;
     if (img) { img.style.top = `${frame.top}px`; /* left/width/height */ }
     return frame;
   }
   ```
   `NotaComicBook` resolves the active page via `#getComicBookPageByFrameId(this.#lastElementId)`.
3. **Active-clone accessor on `NotaComicBook`**: `get #activeClone() { return this.#container.querySelector<HTMLImageElement>('img'); }`

The gesture state lives on `NotaComicBook` (it owns the container + the document-level
listeners). Both plans replace `#initGestureDetection()`.

---

## Plan A′ — JS zoom (layout-size) + native overflow-scroll pan  *(primary)*

**Idea:** zoom by changing the clone's *layout* `width/height` (so the overlay becomes
scrollable), and let the user pan via **native momentum scroll** of the overlay. Pinch is
JS; pan is the browser's scroll (axis-lock + momentum for free).

### CSS (NotaComicBookPage.scss)
Add a manual-mode modifier on the container, toggled by a class (e.g. `nota-comic-manual`):
```scss
div.nota-comicbook-page-container.nota-comic-manual {
  overflow: auto;
  -webkit-overflow-scrolling: touch;   // momentum on iOS
  overscroll-behavior: contain;        // don't chain scroll to the Flutter pager
  touch-action: pan-x pan-y;           // allow native pan, we handle pinch in JS
}
```
Note the base container rule has no `overflow` (visible); only manual mode makes it scroll.

### Gesture handling (NotaComicBook)
State: `#manualOverrideActive`, `#baseW`, `#baseH`, `#pinchStartDist`, `#pinchStartW/H`,
`#pinchStartScrollLeft/Top`, `#focal{x,y}`, plus min/max width bounds.

- **touchstart (≥2 touches):**
  - If not already manual: `freezeAtCurrentFrame()` on the active page → base frame.
    Re-base to scroll coords: set clone `left=0, top=0`, set
    `container.scrollLeft = -frame.left`, `container.scrollTop = -frame.top`, set
    clone `width=frame.width, height=frame.height`. Add `.nota-comic-manual`.
    Fire `updateNarrationSync(false)` once.
  - Record `#pinchStartDist = hypot(t0,t1)`, `#pinchStartW/H` = clone width/height,
    `#pinchStartScrollLeft/Top` = container scroll, `#focal` = midpoint of the two
    touches in container-viewport coords.
- **touchmove (≥2 touches):**
  - `ratio = hypot(now)/#pinchStartDist`; `newW = clamp(#pinchStartW*ratio, minW, maxW)`;
    `newH = newW * (baseH/baseW)` (preserve aspect).
  - Apply `clone.style.width/height = newW/newH`.
  - **Keep focal point stationary** (zoom-to-fingers):
    ```
    contentX = #pinchStartScrollLeft + focal.x
    scrollLeft = contentX * (newW / #pinchStartW) - focal.x
    ```
    same for Y; assign to `container.scrollLeft/Top`.
- **touchend:** nothing required (native scroll continues). Optionally settle bounds.
- **Single-finger pan when zoomed:** no JS — native overflow scroll handles it.

### Bounds
- `minW` = full-page fit (`ComicBookCalc.calcFullPageComicFrame(...)` width) so the user
  can't zoom out past the whole page.
- `maxW` = e.g. `canvasSize.width` (native image px) or `minW * 4`.

### Reset (clearManualOverride)
```ts
public clearManualOverride(): void {
  this.#manualOverrideActive = false;
  const c = this.#container;
  c.classList.remove('nota-comic-manual');
  c.scrollLeft = 0; c.scrollTop = 0;
  // next narration cue re-animates the clone frame; nothing else to undo
}
```
The native Re-sync path already calls this before replaying the locator, so the deferred
cue re-pans cleanly.

### Key risks to validate (this is the "test how well it works" part)
1. **Abs-pos overflow scroll:** an absolutely-positioned clone larger than the container —
   does WebKit/Android WebView actually make it scrollable under `overflow:auto`? (WebKit
   generally yes for `width/height`-driven overflow; confirm on device.) If not, wrap the
   clone in a sizer `<div>` whose `width/height` = zoomed size and let the clone fill it.
2. **Triptych conflict:** when zoomed, does single-finger pan scroll the overlay *without*
   the Flutter PageView eating the horizontal gesture? `overscroll-behavior: contain`
   should help. **This is the make-or-break test** — it's exactly where the old branch failed.
3. **Focal-point math** feels right (zoom toward fingers, no drift).

If (1) or (2) fail and can't be made reliable → fall back to Plan A.

---

## Plan A — JS transform zoom + 2-finger transform pan  *(fallback)*

**Idea:** everything in transform space on the clone. No scroll container, no abs-pos
overflow concerns, no native-pager interaction. Pan is **2-finger** (single finger stays
free for the triptych pager).

### Gesture handling (NotaComicBook)
State: `#scale`, `#tx`, `#ty`, and per-gesture start snapshots + start centroid.

- Maintain a transform on the active clone:
  `clone.style.transform = translate(#tx, #ty) scale(#scale)` with
  `clone.style.transformOrigin = '0 0'` (origin at top-left makes the focal math uniform).
- **touchstart (≥2):** if not manual, freeze + `updateNarrationSync(false)` once. Snapshot
  `#startScale=#scale`, `#startTx/Ty`, `#startDist`, `#startCentroid` (midpoint).
- **touchmove (≥2):**
  - `ratio = dist/#startDist`; `newScale = clamp(#startScale*ratio, minScale, maxScale)`.
  - Zoom about the centroid C: `tx = C.x - (C.x - #startTx) * (newScale/#startScale)` (same Y).
  - Add pan: `tx += centroidNow.x - #startCentroid.x` (same Y) so a 2-finger drag pans.
  - Clamp `tx/ty` so the scaled image can't be dragged fully off-screen.
- **Single finger:** ignored → triptych pager pages as normal.

### Bounds
`minScale = 1` (fit, the narration baseline), `maxScale = 4`.

### Reset (clearManualOverride)
```ts
this.#manualOverrideActive = false;
this.#scale = 1; this.#tx = 0; this.#ty = 0;
const img = this.#activeClone; if (img) img.style.transform = '';
```
Caveat: the narration animation animates `top/left/width/height`, not `transform`, so a
leftover transform composes with it. Always clear transform on reset (above) and on each
new `gotoComicFrame` start (clear transform when a fresh cue animates) to avoid drift.

### Trade-offs vs A′
- Pro: robust, cross-platform identical, no pager/abs-pos risk, trivial reset.
- Con: pan is 2-finger only (no momentum, no single-finger drag).

---

## Validation (both)

Run example on iOS sim with the Nota comic (`merkur:libraryid:50272`) + narration:
1. Pinch → narration desyncs (manual mode chip / state).
2. Zoom centers on fingers; image stays put under fingers.
3. Pan: A′ = single-finger native scroll; A = 2-finger drag.
4. **Triptych:** single-finger horizontal swipe still turns the page when NOT zoomed.
5. Tap **Re-sync** → zoom/pan resets, view re-pans to the current narrated panel.
6. Cross-resource page turn during manual mode still works.

Honesty: native iOS behavior can't be seen in marionette screenshots — verify on the
simulator/device directly (`xcrun simctl io booted screenshot` or by feel).

## Cleanup / changelog
- Remove iOS `resetWebViewZoom()` (probe).
- CHANGELOG: the consumer-visible new behavior is "pinch-zoom a comic panel during
  narration (enters manual mode); Re-sync restores zoom and re-pans." NOT "panel pan/zoom
  during narration" (that already shipped). Hold the rewrite until validated.
