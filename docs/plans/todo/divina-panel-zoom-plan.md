# DiViNA+GuidedNav narrated panel zoom — implementation plan

## Goal

Bring narrated panel pan/zoom to DiViNA+GuidedNav comics (CBZ/DiViNa profile) on
iOS and Android, matching the EPUB+MO experience already shipping. Each narration cue
zooms to the `imgref` panel; the first manual pinch enters manual mode; Re-sync and
stop behave identically to the EPUB+MO path.

---

## Rendering model (what we're working inside)

### iOS

DiViNA FXL is rendered by the existing `EPUBNavigatorViewController` (same navigator
as EPUB). Each spine item is wrapped in `fxl-spread-one.html` (outer frame) which
hosts an inner `<iframe>` whose `src` is the page image served as a minimal HTML file.
The inner HTML contains only `<img src="…">` — no `<figure>` or `<div.area>` panel
structure exists in the DOM.

JS is injectable into the outer frame via `readiumViewController.evaluateJavaScript`
and into the inner frame via `window.spread.eval('', code)`. However, this is **not
the chosen approach** — see Approach A rejection below.

### Android

DiViNA uses `ComicNavigator` wrapping Readium's `ImageNavigatorFragment`, backed by a
native `PhotoView`. There is **no WebView** — JS injection is not possible.

### Panel coordinate source

Panel geometry lives entirely in `guided-navigation.json` as:

```json
{ "imgref": "image0001.jpg#xywh=pixel:44,113,757,226", "audioref": "...", "textref": "..." }
```

`xywh` values are in authored canvas-pixel space (the same px coordinate system as the
source XHTML `<div.area>` elements). Image intrinsic dimensions are available from the
manifest reading-order entries (`width`, `height`).

---

## Why not JS injection into the FXL inner iframe (Approach A)

- Android's `ImageNavigatorFragment` has no WebView — a parallel native implementation
  would be required regardless, making the JS path iOS-only with no code sharing.
- `window.spread.eval` is an undocumented Readium internal of the FXL spread HTML.
  Coupling to it would be fragile across upstream toolkit upgrades.
- Three coordinate spaces must be reconciled: authored `xywh` canvas-px → image
  intrinsic px → inner iframe viewport px. Keeping this correct across arbitrary image
  sizes is error-prone in JS without strong typing.

---

## Chosen approach — native "DiViNA zoom controller" (Approach B)

A thin native component on each platform reads the guided-nav `imgref` coords and
drives zoom/pan directly. No JS, no TS, no Dart changes.

The existing narration-sync bridge (`onNarrationSyncChanged` /
`setNarrationSyncEnabled` / stop) is reused unchanged.

---

## iOS implementation

### `DiViNaZoomController` (new class in `EPUBReaderView.swift` or its own file)

**Responsibilities:**
- Own a transparent `UIView` overlay, added as a sibling above the
  `EPUBNavigatorViewController` view in the container hierarchy.
- Accept pan/zoom cue calls from `EPUBReaderView` with a parsed `PanelRegion`
  (normalised 0–1 fractions of the image).
- Animate zoom-to-panel (Ken Burns) using `CABasicAnimation` on its own sublayer,
  or via `UIViewPropertyAnimator` on a child `UIImageView` that fills the overlay.
- Handle `UIPinchGestureRecognizer` for manual-zoom entry (fires
  `window.updateNarrationSync(false)` via the existing JS bridge).
- `resetInstant()` — zeroes transform with no animation (stop behaviour).
- `resetAnimated()` — returns to full-page with a short animation (Re-sync behaviour).

**Image source**: load the current spine item's image into a child `UIImageView`
(fill-overlay, `contentMode = .scaleAspectFit`). This requires one extra image load
per page turn but keeps the overlay fully independent from the WKWebView layout — no
risk of interfering with Readium's FXL transform or scroll state.

**Panel region computation** (pure math, no WebView):

```
scale = max(viewportW / panelW, viewportH / panelH)  // zoom that fills the screen
focalX = panelCx / imageW * imageViewW                // centre in UIImageView coords
focalY = panelCy / imageH * imageViewH
transform = CGAffineTransform(scaleX: scale, y: scale)
  .translatedBy(x: viewportCx - focalX, y: viewportCy - focalY)
```

where `panelCx/Cy` = `x + w/2`, `y + h/2` from the `#xywh=pixel:` fragment;
`imageViewW/H` = overlay frame size (image fills it aspect-fit); `viewportCx/Cy` =
overlay centre.

**Cue entry point** — called from `EPUBReaderView.performSyncNavigation`:

```swift
if let region = parseImgref(currentCue.imgref) {
    divinaZoomController?.zoomToPanel(region, duration: segmentDuration)
}
```

**Stop entry point** — called from `EPUBReaderView.resetForNarrationStop`:

```swift
divinaZoomController?.resetInstant()
```

**Re-sync entry point** — called from `EPUBReaderView.setNarrationSyncEnabled(true)`:

```swift
divinaZoomController?.resetAnimated()
// existing deferred-locator replay follows
```

### `parseImgref` helper (pure, no async)

```swift
// "image0001.jpg#xywh=pixel:44,113,757,226" → PanelRegion(x:44, y:113, w:757, h:226)
// nil for whole-image refs (no fragment, or fragment without xywh)
```

### Image loading per page

When `onJumpToLocator` fires (page changed), the controller loads the new image:

```swift
func loadImage(for locator: Locator) {
    guard let href = locator.href, let url = publication.url(for: href) else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data, let img = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.imageView.image = img }
    }.resume()
}
```

For local `.divina` files the URL is a `file://` URL — the load is fast/synchronous
enough that the overlay is ready before the first cue fires.

### Files changed (iOS)

- `EPUBReaderView.swift` — instantiate and wire `DiViNaZoomController`; call
  `zoomToPanel` in `performSyncNavigation`; call `resetInstant` in
  `resetForNarrationStop`; call `loadImage` in `onJumpToLocator`.
- New file: `DiViNaZoomController.swift` (or inner class/extension of `EPUBReaderView`).

---

## Android implementation

### `ComicNavigator` additions

`PhotoView` (the Readium image page view) already supports programmatic zoom:
`photoView.setScale(scale, focalX, focalY, animate)`.

The view tree walk is already written in `ComicNavigator.clearComicInsets` — extract
it into a `findPhotoView(view: View?): PhotoView?` helper.

**`zoomToPanel(imgref: String, imageWidth: Int, imageHeight: Int, animate: Boolean)`**

```kotlin
suspend fun zoomToPanel(imgref: String, imageW: Int, imageH: Int, animate: Boolean) {
    val region = parseImgref(imgref) ?: return  // null = whole image, skip zoom
    val pv = findPhotoView(imageNavigator?.view) ?: return
    withMainContext {
        val viewW = pv.width.toFloat()
        val viewH = pv.height.toFloat()
        val scaleX = viewW / (region.w * viewW / imageW)
        val scaleY = viewH / (region.h * viewH / imageH)
        val scale = max(scaleX, scaleY).coerceAtMost(MAX_ZOOM)
        val focalX = (region.x + region.w / 2f) * viewW / imageW
        val focalY = (region.y + region.h / 2f) * viewH / imageH
        pv.setScale(scale, focalX, focalY, animate)
    }
}
```

**Manual-mode detection** — `PhotoView.setOnScaleChangeListener` fires whenever the
user pinch-zooms. Install in `setupNavigatorListeners`:

```kotlin
findPhotoView(navigator.view)?.setOnScaleChangeListener { scaleFactor, _, _ ->
    if (scaleFactor != 1f) {
        visualListener.onManualZoomDetected()  // new callback on VisualListener
    }
}
```

`ReadiumReader` maps `onManualZoomDetected` → `setNarrationSyncEnabled(false)`.

**Reset on stop** — `ComicNavigator.resetZoom()`:

```kotlin
suspend fun resetZoom(animate: Boolean) {
    val pv = findPhotoView(imageNavigator?.view) ?: return
    withMainContext { pv.setScale(1f, animate) }
}
```

Called from `ReadiumReader.exitNarrationMode()`.

**`parseImgref`** (pure Kotlin):

```kotlin
// "image.jpg#xywh=pixel:44,113,757,226" → Rect(44, 113, 801, 339)  (right/bottom form)
// null for whole-image refs
private fun parseImgref(imgref: String): android.graphics.RectF? { … }
```

### Files changed (Android)

- `ComicNavigator.kt` — add `zoomToPanel`, `resetZoom`, `findPhotoView`,
  `parseImgref`; install scale listener in `setupNavigatorListeners`.
- `ReadiumReader.kt` — call `comicNavigator?.zoomToPanel(...)` when a guided-nav cue
  fires in the narration sync path; call `comicNavigator?.resetZoom(false)` in
  `exitNarrationMode`.
- `EpubNavigator.kt` `VisualListener` interface — add `onManualZoomDetected()`.

---

## Narration cue wiring

The guided-nav cue contains the `imgref` for the current panel. The narration sync
path already receives this through `FlutterMediaOverlayItem` (converted from
`GuidedNavigationObject`). The `imgref` field needs to be plumbed to the zoom call:

- iOS: `FlutterMediaOverlayItem` → `performSyncNavigation` already receives the cue;
  add an `imgref: String?` field to `FlutterMediaOverlayItem` and populate it from
  `GuidedNavigationDocument.toMediaOverlays`.
- Android: same — add `imgref` to the Kotlin `FlutterMediaOverlayItem`, populate from
  `GuidedNavigationDocument.toMediaOverlays`, pass to `comicNavigator.zoomToPanel`.

Files: `FlutterMediaOverlayItem.swift`, `FlutterMediaOverlay.swift` (iOS);
`FlutterMediaOverlayItem.kt` (Android); `GuidedNavigationDocument.swift/.kt`.

---

## Shared behaviour contract

| Event | iOS | Android |
|-------|-----|---------|
| Narration cue with panel region | `zoomToPanel(region, duration)` | `zoomToPanel(imgref, …, animate=true)` |
| Narration cue without region (whole image) | no zoom / stay at current | same |
| Manual pinch | `UIPinchGestureRecognizer` → `updateNarrationSync(false)` | `setOnScaleChangeListener` → `onManualZoomDetected()` |
| Re-sync (`setNarrationSyncEnabled(true)`) | `resetAnimated()` then replay cue | `resetZoom(animate=true)` then replay cue |
| Stop | `resetInstant()` | `resetZoom(animate=false)` |
| Page turn | load new image into UIImageView | PhotoView already shows new image |

---

## Verification

Test publication: `50272-nota-comics.divina` (already in `example/assets/pubs/`).

1. Open the DiViNA comic and tap play.
2. Confirm each narration cue zooms (Ken Burns) to the `imgref` panel region.
3. Pinch manually → `onNarrationSyncChanged(false)` fires (Re-sync control appears).
4. Tap Re-sync → zoom resets, view snaps to current narrated panel.
5. Stop → instant return to full-page view; pinch-zoom still usable.
6. Page-turn mid-narration → correct image loaded in overlay, zoom continues.
7. Repeat 1–6 on Android device/emulator.

Whole-image cues (no `#xywh` fragment, e.g. cover and title sections) should leave the
view at the current zoom level without animating.

---

## Known limitations / deferred

- **Android B&W mode**: already documented as unimplemented in `ComicNavigator.kt` for
  the same PhotoView reason (`ColorMatrixColorFilter` requires fragile view-tree walking).
  Panel zoom does not change this.
- **iOS image cache**: no caching layer — each page turn triggers a fresh load. Acceptable
  for local `.divina` files; revisit if remote streaming comics become common.
- **Max zoom cap**: `MAX_ZOOM` on Android should match the existing PhotoView default
  (typically 3×). On iOS use a matching cap in the `CATransform3D` scale.
