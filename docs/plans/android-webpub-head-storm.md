> **✅ Implemented on Android and iOS (2026-10-22).** Plugin-side options A1 + B landed on `main`:
> `ReadiumReader.assetToPublication` swaps in `PerResourcePositionsService` for
> bare-manifest (resource-asset) EPUB-profile publications; `injectScriptsAndStyles` takes
> the filename from the container URL instead of `resource.properties()`. Option C (upstream
> report) intentionally not filed. iOS (A1 equivalent): the `onCreatePublication` hook in
> `FlutterReadiumPlugin.swift` applies the same override. Both platforms gate on the asset
> kind (`asset is ResourceAsset` / `if case .resource = asset`) — streamed publications are
> opened as a single resource, archives as a container. Both device-verified; before/after
> captures in Verification.

# Android streamed-WebPub HEAD/GET storm at player open — investigation + fix plan

## Problem

Opening a streamed WebPub (`application/webpub+json`, reflowable HTML) on Android issues
**one HEAD request — and one full GET — for every HTML file in the publication** when the
player page opens, before the first page renders. Local (zip) EPUBs are unaffected.
*Correction (2026-10-22, verified on iOS simulator):* the original note here claimed iOS
was unaffected; that was wrong. iOS runs the same positions probe storm — one HEAD per
reading-order chapter at open (see iOS capture below) — because swift-toolkit's
`EPUBNavigatorViewController.initialize()` awaits `positionsByReadingOrder()` before
building the pagination view, and its `EPUBPositionsService` hits
`HTTPResource.properties()`/`estimatedLength()` (HEAD; per-instance cache only, since
`HTTPContainer` hands out a fresh `HTTPResource` per lookup). It lacks the injection
full-GET amplification (iOS injects via `WKUserScript`, not `TransformingResource`).
The A1 fix now covers both platforms: the iOS port landed 2026-10-22 (after-capture
below). Reported from LYT4; the app side is clean — it only calls `openPublication` and
enables the navigator. All traffic originates natively.

Diagnosed 2026-10-22 against readium/kotlin-toolkit **3.4.0** (`readium_version` in
`flutter_readium/android/build.gradle`).

## Root cause chain

All toolkit paths below are `readium/<module>/src/main/java/...` in the kotlin-toolkit at
tag 3.4.0; plugin paths are in `flutter_readium/android/src/main/kotlin/dk/nota/flutterreadium/`.

1. **Streamed WebPub → one `HttpResource` per file.**
   `ReadiumWebPubParser.parseResourceAsset` builds a `CompositeContainer(SingleResourceContainer(manifest.json), HttpContainer(...))`
   (`streamer/parser/readium/ReadiumWebPubParser.kt:212-218`), so every reading-order/resource
   link resolves to an `HttpResource` (`shared/util/http/HttpContainer.kt:29-40`).
   `HttpContainer.get()` creates a **fresh** `HttpResource` per lookup — its per-instance
   `_headResponse` cache never survives across passes.

2. **EPUB-profile WebPub gets `EpubPositionsService` with a network-touching strategy.**
   Books that render in our EPUB navigator declare `conformsTo: epub` (`epubEnable` requires
   it — `ReadiumReader.kt:990-993`; profile matching is explicit in the manifest,
   `shared/publication/Manifest.kt:52-55`). The parser then registers
   `EpubPositionsService.createFactory(epubReflowablePositionsStrategy)`
   (`ReadiumWebPubParser.kt:106-117`) with the default
   `ReflowableStrategy.recommended = ArchiveEntryLength(pageLength = 1024)`.
   `DefaultPublicationParser` hardcodes `ReadiumWebPubParser(context, httpClient, pdfFactory)`
   without exposing the strategy (`streamer/parser/PublicationParser.kt:63-78`), so the plugin
   currently always gets the default.

3. **Position computation costs network per HTML file.**
   `EpubPositionsService.ReflowableStrategy.ArchiveEntryLength.positionCount()` calls
   `resource.properties()` (no archive metadata for HTTP → null) and falls back to
   `resource.length()` (`streamer/parser/epub/EpubPositionsService.kt:83-90`). On `HttpResource`
   both go through `headResponse()` → **one HEAD per file**
   (`shared/util/http/HttpResource.kt:37-49, 85-93`).
   Worse, positions run against resources wrapped by our injection `TransformingContainer`:
   `TransformingResource` delegates `properties()` but overrides `length()` as `bytes().size`
   (`shared/util/resource/TransformingResource.kt:31, 59-67, 86-87`), so the fallback `length()`
   **downloads the full body of every chapter** after the HEAD. Captures therefore show
   N × (HEAD + GET) at open, not just HEADs.

4. **Trigger at page open (plugin-side, deliberate).**
   `ReadiumReader.epubEnable` pre-warms `pub.positionsByReadingOrder()` on the I/O dispatcher
   (`ReadiumReader.kt:999-1005`, commits `8ed28832`, `a05d2739`) because
   `EpubNavigatorFragment` computes the same list with `runBlocking` on the main thread in its
   constructor (`navigator/epub/EpubNavigatorFragment.kt:323-327`). The pre-warm moved the storm
   off the main thread but kept it eager — every streamed WebPub open pays it. Removing the
   pre-warm is not a fix: the fragment constructor triggers the identical computation anyway.

## Fix options

### A. Plugin-side: override `positionsServiceFactory` for HTTP-backed publications (recommended)

`ReadiumReader.assetToPublication` already hooks `onCreatePublication`
(`ReadiumReader.kt:613-623`). When the publication's container is HTTP-backed (streamed
WebPub), set `servicesBuilder.positionsServiceFactory` to a service that never touches
resources:

- **A1 — `PerResourcePositionsService`** (toolkit ships it for DiViNa webpubs): one position
  per reading-order resource, zero network. Trade-off: coarse progress bar / progression math
  for long single-chapter publications; `totalProgression` granularity drops.
- **A2 — custom plugin-owned `PositionsService`**: keep the 1024-byte page model without the
  network. Either derive counts from manifest link metadata where present, or — simplest
  correct variant — fall back to a fixed position count per resource. Same granularity caveat
  as A1 unless Nota manifests carry per-link `length`.

How to detect "streamed": the asset handed to the open pipeline is a **single-resource
asset** (bare manifest) rather than a container asset — archives, including remote zips,
open as containers and keep byte-granular positions. The shipped gate is `asset is
ResourceAsset` (Kotlin) / `if case .resource = asset` (Swift), one predicate on both
platforms. (The first iOS cut keyed off the HTTP open URL; review showed it also matches
remote zip EPUBs, and the first Android cut keyed off an HTTP `self` link, which manifests
without one legitimately lack — asset kind is the exact signal.)

Note: neither built-in `EpubPositionsService` strategy is network-free for HTTP containers —
`OriginalLength` only avoids the HEAD if `Link.properties.encryption.originalLength` is set
(`EpubPositionsService.kt:69-76`), which streamed WebPubs don't carry. So a factory override
(or option C), not a strategy swap, is the lever available to us.

### B. Plugin-side secondary: kill the per-page-load HEAD in injection

`injectScriptsAndStyles` calls `this.properties()` only to read a filename
(`ReadiumExtensions.kt:192`) — on a fresh `HttpResource` that's one HEAD per chapter on first
render, and it repeats because containers hand out new resource instances. Derive the filename
from the href/link instead (the transform already matches on `filename.endsWith("html")`;
`url.extension` is available at the `TransformingContainer` call site,
`ReadiumReader.kt:746-765`). Pure win, no behavior change.

### C. Upstream report to readium/kotlin-toolkit

File an issue (and it's a candidate for a small PR):
- `ArchiveEntryLength.positionCount()` should not fall back to `resource.length()` per resource
  when the container isn't archive-backed (or `EpubPositionsService` should receive lengths from
  the manifest), and/or
- `HttpContainer` should cache `HttpResource` instances per URL so `_headResponse` dedupes the
  repeated HEADs across passes.

Option A/B make the plugin correct regardless; C fixes it for everyone.

## Explicitly not the fix

- Removing the `epubEnable` pre-warm: `EpubNavigatorFragment`'s constructor `runBlocking`
  performs the same `positionsByReadingOrder()` call; removing the pre-warm only moves the
  storm back onto the main thread.
- Expecting `WebPositionsService` to help: it only fetches a precomputed positions list if the
  manifest exposes a link with media type `application/vnd.readium.position-list+json`
  (`shared/publication/services/PositionsService.kt:137-150`); Nota manifests don't. If the
  server team ever adds one, that becomes a zero-code plugin option.

## Verification

1. Proxy/logcat a streamed WebPub open on Android before the change: expect
   N × (HEAD + GET) burst over HTML files at `epubEnable`.
2. After the fix: burst gone; only the manifest + currently-read chapter(s) are fetched.
3. Behavior checks (positions consumers): progress slider movement, `totalProgression` in
   locators, lastmark restore, TOC jump, and narration-sync scroll positioning still behave —
   A1/A2 change position granularity, confirm it's acceptable in the LYT4 player UI.
4. Regression: open a zip EPUB and a DiViNa webpub; positions come from other paths and must be
   untouched.

### Capture results (2026-10-22, emulator API 36, debug build)

Instrumented `DefaultHttpClient.Callback.onStartRequest` with a `PluginLog.d("HTTPCAP",
"${method} ${url}")` and toggled the A1 override via a temporary `STORM_REPRO` const, then
opened the streamed fixture
`https://merkur.nota.dk/opds2/publication/free/merkur:libraryid:50272/stream/WebPubText/manifest.json`
(4 `text/html` reading-order links) from the example app's shelf. Requests within ~1.5s of
the tap, path segment relative to `.../WebPubText/`:

|Request|Before (A1 disabled)|After (A1 enabled)|
|---|---|---|
|manifest.json HEAD|1|1|
|manifest.json GET|3|3|
|chapter HEAD (`0001`–`0004`)|**4** (one per chapter)|**0**|
|chapter GET (`0001`,`0002`)|2|2|
|image0001.jpg HEAD+GET|1+1|1+1|

Before shows the `EpubPositionsService` probe storm: one HEAD per chapter across all 4
reading-order links — including `0003`/`0004`, which the navigator never opened (the four
HEADs fire back-to-back at `25.634`–`25.752`, before first paint). After shows zero chapter
HEADs. The 2 chapter GETs in both captures are the navigator's adjacent-page prefetch.
Note: the source-derived prediction that each positions probe would also issue a full GET
per chapter (via `TransformingResource.length()` = `bytes().size`) did not reproduce — no
GETs for `0003`/`0004` appeared within the ~15s window, so the probes were satisfied by
HEAD responses alone. Either way, the HEAD-per-chapter burst on the open path is the
confirmed signature, and the A1 override eliminates it entirely.

Fix B was not flag-gated (both runs already had it): the after-capture renders chapters
`0001`/`0002` with no HEAD preceding either GET, which is the observable proof that
`injectScriptsAndStyles` no longer calls `properties()` on chapter load.

Behavior checks from the plan's checklist were exercised only as far as first paint: the
reader rendered content and drew the seek slider at the start position in both captures.
TOC jump, lastmark restore, and narration-sync scroll positioning were not exercised on
device. The zip-EPUB and DiViNa regression (checklist item 4) was likewise not re-run;
those profiles keep their own positions services — the A1 override is gated on the asset
being a bare-manifest resource asset inside the `conformsTo(EPUB)` branch, and fix B touches
only the injection filename source — so neither behavior changes, but that reasoning is not
device-verified here.

### iOS capture (2026-10-22, iPhone 17 Pro simulator)

Same fixture, opened from the example shelf. Captured via the plugin's existing
`DefaultHTTPClientDelegate.willStartRequest` logging (`Readium.swift:143`, os.log
subsystem `dk.nota.flutter_readium`; the before-capture needed no extra instrumentation). Within ~2.5s of the
tap: manifest GET ×2, then **4 chapter HEADs back-to-back** (16:30:15.6–15.7, one per
reading-order link, ahead of first paint), then full GETs of all 4 chapters + 3 images
(iOS preloadNextPositionCount=6 pulls the whole 4-chapter book into the webview).
The HEAD-per-chapter positions burst is identical to Android pre-fix; the extra full
chapter GETs here are navigator preload, not the Android injection amplification (iOS
injects via `WKUserScript`, no `TransformingResource`/`properties()` HEAD exists on this
path). Conclusion: one HEAD per chapter at open, same as Android pre-fix.

**After the iOS fix (same simulator, same fixture, patched plugin):** open issued
manifest GET ×2 then chapter GETs only — **zero chapter HEADs**; first content GET
0.49 s after the manifest vs 1.29 s pre-fix. The image HEAD+GET pairs are the
navigator's own preload and are unchanged. The reader opened and rendered chapter 1;
pagination and the progress bar behaved (one position per chapter). Zip-EPUB and DiViNa
parsing were not re-run post-fix; the override is gated on the asset being a bare-manifest
resource asset and cannot fire for them — that reasoning is not device-verified here.

## Consumer-visible position/progression semantics (post-fix)

The override replaces `EpubPositionsService` with `PerResourcePositionsService`, so a
streamed publication now has one position per reading-order chapter. What that means per
platform differs, and it is documented here rather than in the CHANGELOG:

- **Position index (`Locator.locations.position`)** — chapter-granular on both platforms.
  Android: `EpubNavigatorFragment.notifyCurrentLocation` copies `locations` from the picked
  position locator (index = `ceil(progression * (size - 1))` into the per-resource positions)
  and overrides only `progression`, so `totalProgression` steps per chapter too
  (kotlin-toolkit 3.4.0, no interpolation). iOS: position indices come from
  `positionsByReadingOrder()`, one per chapter.
- **Emitted progress (`Locator.totalProgression`)** — Android becomes chapter-granular
  (start of chapter k of n ≈ (k-1)/n). iOS stays **continuous**: swift-toolkit 3.11.0
  `EPUBViewportAndLocationCalculator` + `ViewportProgressionCalculator` interpolate the
  in-resource progression across the chapter's equal share, so halfway through the first of
  four chapters yields ~0.125, not 0. Consumers treating `totalProgression` as fine-grained
  input (e.g. remapping a stored lastmark onto changed content) must expect the coarser
  Android steps; iOS progress is unaffected.
- **iOS navigator preload** — `preloadPreviousPositionCount` / `preloadNextPositionCount` are
  measured in positions, so for streamed publications they now correspond to chapters rather
  than pages; lower them if bandwidth or memory is a concern.
