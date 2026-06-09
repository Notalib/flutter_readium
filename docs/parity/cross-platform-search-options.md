# Cross-Platform Search Options

**Type:** Upstream feature
**Platforms affected:** iOS, Android (Web: out of scope until web-search.md is done)
**Estimated effort:** M

## Context

Both the swift-toolkit and kotlin-toolkit expose a `SearchOptions` struct / class alongside their `SearchService`. A consumer that needs case-sensitive search, whole-word matching, or regex-based search has no way to specify these constraints through the current Dart API — `searchInPublication(query)` is a plain string call with no options. This forces consumers to do their own post-filtering on the (potentially very large) result list.

The upstream options surface is well-defined and symmetric across both native toolkits:

- **caseSensitive** (`Bool?` / `Boolean?`)
- **diacriticSensitive** (`Bool?` / `Boolean?`)
- **wholeWord** (`Bool?` / `Boolean?`)
- **exact** (`Bool?` / `Boolean?`) — match including stop words
- **language** (`String?`) — BCP 47 override
- **regularExpression** (`Bool?` / `Boolean?`)

## Current state

- **Platform interface** (`flutter_readium_platform_interface/lib/flutter_readium_platform_interface.dart` line 154): `Future<List<TextSearchResult>> searchInPublication(final String searchKey)` — no options parameter.
- **iOS** (`FlutterReadiumPlugin.swift` lines 468–503): Calls `publication.searchInContentForQuery(query)` — passes no `SearchOptions`, using upstream defaults.
- **Android** (`PublicationChannel.kt` lines 238–263): Calls `ReadiumReader.searchInPublication(query)` — same, no options forwarded.
- **Web**: Not implemented; see [web-search.md](web-search.md).

## Proposed approach

1. **New model** in `flutter_readium_platform_interface/lib/src/shared/publication/dto/`: Add a `SearchOptions` class with hand-written `toJson` / `fromJson` per project conventions. All fields are nullable; null means "use platform default".
2. **Platform interface**: Add an overload (or change the signature) of `searchInPublication` to accept `SearchOptions? options`. Since extending `FlutterReadiumPlatform` is the convention over implementing it, adding a default-valued parameter is non-breaking for existing subclasses.
3. **iOS** (`FlutterReadiumPlugin.swift`): Parse a `searchOptions` field from the method call arguments map and construct a `SearchOptions` instance before calling `publication.search(query:options:)`.
4. **Android** (`PublicationChannel.kt`, `ReadiumReader.kt`): Parse an optional `searchOptions` map from the method call arguments and forward to `publication.search(query, options)` (kotlin-toolkit's `SearchService`).
5. **Method channel**: The `searchInPublication` call in `method_channel_flutter_readium.dart` passes the query string as a plain string today. Change it to pass `[query, options?.toJson()]` (a two-element list); both native sides check for the optional second element and remain backward-compatible if it is absent.

Key files that change:
- `flutter_readium_platform_interface/lib/flutter_readium_platform_interface.dart`
- `flutter_readium_platform_interface/lib/method_channel_flutter_readium.dart`
- `flutter_readium/ios/flutter_readium/Sources/flutter_readium/FlutterReadiumPlugin.swift`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutter_readium/PublicationChannel.kt`
- `flutter_readium/android/src/main/kotlin/dk/nota/flutter_readium/ReadiumReader.kt`

## Scope boundaries

- `otherOptions` (the extensible `Map<String,String>` bucket in the upstream SDK) is out of scope for the first iteration — it has no known consumer use cases and is a toolkit-internal escape hatch.
- Web search options are out of scope until [web-search.md](web-search.md) is implemented.
- Streaming / incremental search results (the upstream `SearchIterator.next()` pattern) remain out of scope; the current collect-all-then-return approach is acceptable.

## Risks / open questions

1. **API shape decision**: Should `SearchOptions` be added as an optional second parameter (`searchInPublication(query, {SearchOptions? options})`), or as a new method (`searchInPublication2`)? The former is cleaner but technically changes the method signature in the platform interface; the latter avoids any risk. The project convention of using `extends` rather than `implements` makes the optional-parameter approach safe.
2. **Kotlin-toolkit `regularExpression` option**: Confirm that kotlin-toolkit 3.2.0 exposes `regularExpression` in its `SearchService.Options`. If not, silently ignore the flag on Android and document the gap.
3. **iOS `caseSensitive` default**: The swift-toolkit `SearchOptions.caseSensitive` defaults to `false`. Passing `null` from Dart should preserve this default; explicitly confirm this during implementation.

## Verification

1. Run `bin/analyze` and `bin/format` from the repo root.
2. Open a publication on iOS and Android in the example app.
3. Call `searchInPublication('The', options: SearchOptions(caseSensitive: true))` — confirm results differ from `caseSensitive: false`.
4. Call `searchInPublication('\\bthe\\b', options: SearchOptions(regularExpression: true))` on iOS — confirm regex matching works.
5. Call `searchInPublication('café', options: SearchOptions(diacriticSensitive: false))` — confirm `cafe` is also returned.
6. Confirm calling with `options: null` (the default) still works correctly on all platforms.
