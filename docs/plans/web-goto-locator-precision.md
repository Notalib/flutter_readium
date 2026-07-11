# Web goToLocator Precision

> **✅ Implemented** on `feat/web-feature-parity`. Web `goToLocator` passes the full serialised `Locator` (cssSelector / progression / text), no longer href-only. Retained for reference.

**Type:** Cross-platform parity
**Platforms affected:** Web
**Estimated effort:** M

## Context

`goToLocator(locator)` is the primary API for restoring a saved reading position and for jumping to search results or bookmarks. On iOS and Android, the navigator accepts the full `Locator` object — including `locations.cssSelector`, `locations.progression`, `locations.position`, and `text.highlight` — and navigates to the exact element within a resource. On web, the implementation navigates only to the resource (chapter) identified by `locator.hrefPath`, ignoring all sub-resource location data. This means:

- A saved position at 30% through Chapter 5 is restored to the beginning of Chapter 5 on web.
- Search results jump to the chapter, not the matching paragraph.
- TTS sync-to-reader (future feature) cannot land at the correct word on web.

The ts-toolkit `EpubNavigator.goTo(locator: Locator)` method accepts a full `Locator` including `locations.cssSelector` and `text.highlight`. The web implementation just needs to pass the full serialised locator instead of only the `href`.

## State at planning time

- **iOS**: `goToLocator` calls `readiumViewController.go(to: locator, ...)` with the full upstream `Locator`. File: `EPUBReaderView.swift` line 434.
- **Android**: `ReadiumReader.visualGoToLocator(locator, animated)` forwards the full `Locator`. File: `ReadiumReaderWidget.kt` line 322.
- **Web** (`reader_widget_web.dart` line 72–84; `flutter_readium_web.dart` line 267–279): Calls `JsPublicationChannel.goToLocation(locator.hrefPath)` — the `hrefPath` is just the resource path with no location metadata. The JS `ReadiumReader.goTo(href)` accepts only a string href.
- `js_publication_channel.dart` line 15: The JS interop `goTo(JSString location)` receives a plain string — not a full locator.

## Landed approach

1. **JS side** (`ReadiumReader.ts`): Replace `async goTo(href: string)` with `async goToLocator(locatorJson: string): Promise<void>` that deserialises the full `Locator` from JSON and calls `this._nav?.goTo(locator, true, callback)` (the ts-toolkit navigator accepts `Locator` objects directly via its `goTo` method, which resolves `cssSelector` and `text.highlight` to the exact DOM position).
2. **JS interop** (`js_publication_channel.dart`): Add `external JSPromise goToLocator(JSString locatorJson)` to the `ReadiumReader` extension type and update `JsPublicationChannel.goToLocation` to call it with the full JSON-encoded locator. Keep backward compatibility with the existing `goTo` if needed by other callers (or remove it if unused).
3. **Dart web plugin** (`flutter_readium_web.dart`) and **web widget** (`reader_widget_web.dart`): Pass `json.encode(locator.toJson())` instead of `locator.hrefPath`.

This follows the project convention of serialising Readium-owned objects (like `Locator`) as JSON strings across JS/Dart boundaries.

## Scope boundaries

- First iteration covers EPUB only — PDF is not supported on web.
- Audio publications (`audioEnable`) on web are a separate gap; this plan is limited to visual navigation.
- The `animated` parameter is passed through but the ts-toolkit web navigator may not support animation; document this if confirmed.

## Risks / open questions

1. **ts-toolkit `goTo` signature**: Verify that `EpubNavigator.goTo(locator: Locator, animated: boolean, callback)` accepts a `Locator` with `locations.cssSelector` and resolves it correctly. If the ts-toolkit's web `goTo` only uses `href`, the precision improvement requires a workaround (e.g. post-navigation JS injection to scroll to the cssSelector element).
2. **Locator.text.highlight fallback**: When `cssSelector` is absent but `text.highlight` is present (common for search results), the ts-toolkit may or may not support highlight-anchored navigation. Confirm this during implementation; document the fallback behaviour.
3. **Breaking change to `ReadiumReader.goTo`**: Other internal callers (e.g. if `goLeft`/`goRight` use it) must not be affected.

## Verification

1. Run `bin/update_web_example` after TS changes.
2. Run `bin/analyze` and `bin/format` from the repo root.
3. Open an EPUB on web, navigate to a specific paragraph, capture the `onTextLocatorChanged` locator.
4. Reload the publication and call `goToLocator` with the captured locator.
5. Confirm via marionette screenshot (or browser devtools) that the scroll position matches the captured paragraph, not the beginning of the chapter.
6. Repeat for a locator with only `progression` (no cssSelector) — confirm the reader scrolls to the corresponding percentage of the chapter.
