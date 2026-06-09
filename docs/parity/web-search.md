# Web Content Search

**Type:** Cross-platform parity
**Platforms affected:** Web
**Estimated effort:** M

## Context

`searchInPublication(query)` lets consumers build chapter-level or full-book search UIs on top of the plugin. The feature works on iOS (using swift-toolkit's `SearchService`) and Android (using kotlin-toolkit's `SearchService`). On web the method is simply not implemented — the `FlutterReadiumWebPlugin` inherits the `FlutterReadiumPlatform` default which throws `UnimplementedError`. Any consumer that calls `searchInPublication` on web will receive an exception at runtime with no graceful fallback.

The ts-toolkit's `@readium/shared` package exposes `Publication` with a `findAll(locator)` helper and the standard Readium Web Publication Manifest, while `@readium/navigator` gives access to the publication's resources. A text search implementation can fetch resource HTML and scan it with a regex or string matcher, converting matches to `Locator` objects — the same approach the swift-toolkit's `StringSearchService` uses internally.

## Current state

- **iOS**: `searchInPublication` calls `publication.searchInContentForQuery(query)` which delegates to swift-toolkit's `SearchService`. Results are returned as `[TextSearchResult]` JSON-encoded strings. File: `FlutterReadiumPlugin.swift` lines 468–503.
- **Android**: Calls `ReadiumReader.searchInPublication(query)` which uses `kotlin-toolkit`'s `publication.search()`. File: `PublicationChannel.kt` lines 238–263.
- **Web**: `FlutterReadiumWebPlugin` does not override `searchInPublication`; the base implementation throws `UnimplementedError`.

## Proposed approach

Because the ts-toolkit does not bundle a ready-made `SearchService` equivalent on the web (unlike the native toolkits), the search logic must live in the `ReadiumReader.ts` bundle:

1. **JS side** (`ReadiumReader.ts`): Add `async searchInPublication(query: string): Promise<string>` that:
   - Iterates the publication's `readingOrder` links.
   - Fetches each resource's HTML text via `this._publication.get(link).readAsString()`.
   - Scans for case-insensitive occurrences of `query` using a DOM parser or `indexOf`.
   - For each match, constructs a `Locator` with `href`, `type`, `locations.cssSelector` (or `text.highlight`) and `title` (from the matching ToC entry if available).
   - Returns a JSON string of `TextSearchResult[]`.
2. **JS interop** (`js_publication_channel.dart`): Add `external JSPromise<JSString> searchInPublication(JSString query)` to the `ReadiumReader` extension type; add a `JsPublicationChannel.searchInPublication(query)` wrapper.
3. **Dart web plugin** (`flutter_readium_web.dart`): Override `searchInPublication` to call the JS wrapper and parse the returned JSON into `List<TextSearchResult>`.

Follow the JSON-string convention: the returned list should match what iOS/Android return (see `TextSearchResult.toJson()` in `flutter_readium_platform_interface/lib/src/shared/publication/dto/text_search_result.dart`).

After TS changes run `bin/update_web_example`.

## Scope boundaries

- First iteration: plain case-insensitive substring search only. The upstream `SearchOptions` fields (caseSensitive, wholeWord, diacriticSensitive, regex) are a follow-up per [cross-platform-search-options.md](cross-platform-search-options.md).
- No incremental/streaming results for the first iteration — collect all results and return them in one list, matching the current iOS/Android behaviour.
- The `pageNumbers` field on `TextSearchResult` will be `null` on web (same as Android today).
- Fixed-layout EPUB resources may be harder to parse; mark them as a known limitation.

## Risks / open questions

1. **Performance**: Searching all resources in a large EPUB by fetching and scanning each one sequentially in JS can be slow (seconds to tens of seconds). A progress indicator on the Dart side would improve UX, but the current `searchInPublication` API is one-shot (no streaming). Consider a timeout or early-exit after N results.
2. **DOM parsing accuracy**: Building accurate CSS selectors from regex match positions inside raw HTML is non-trivial. A simpler approach (returning only `text.highlight` and no `cssSelector`) is acceptable for a first pass, since consumers primarily use locators from search results to navigate via `goToLocator`, and the ts-toolkit web navigator accepts locators with only an `href` + `text.highlight`.
3. **Locator round-trip fidelity**: The web `goToLocator` currently navigates at resource-level only (see [web-goto-locator-precision.md](web-goto-locator-precision.md)). Until that plan is implemented, search result navigation on web will jump to the chapter but not the exact paragraph.

## Verification

1. Run `bin/update_web_example` after TS changes.
2. Run `bin/analyze` and `bin/format` from the repo root.
3. Launch the example app on web and open an EPUB with known content.
4. Call `searchInPublication('some known word')` and confirm results are returned as `List<TextSearchResult>` with correct `locator.href` and `chapterTitle`.
5. Call `goToLocator(result.locator)` for a result and confirm the reader navigates to the correct chapter.
6. Call `searchInPublication('zzznomatch')` and confirm an empty list (not an exception) is returned.
