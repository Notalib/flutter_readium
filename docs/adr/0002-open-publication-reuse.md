# ADR 0002: Loading and re-opening the open publication

- **Status:** Accepted
- **Date:** 2026-10-23
- **Scope:** `loadPublication` and `openPublication` on iOS, Android, and web
- **Discussion:** [PR #289](https://github.com/Notalib/flutter_readium/pull/289#issuecomment-6344753866)

## Context

Only one publication can be open at a time. Apps routinely call `loadPublication` and `openPublication` with the URL of the publication that is already open: a bookshelf that loads every book's manifest, a reader screen that is pushed again, or a Flutter hot restart, after which native state survives while Dart state does not.

The platforms disagreed on what those calls do:

| Platform | `loadPublication(url)` while that URL is open | `openPublication(url)` while that URL is open |
|---|---|---|
| iOS | Returns the open publication's manifest | Returns the open publication |
| Android | Returned the open publication, which the channel then closed; the reader went blank | Returned the closed publication |
| Web | Fetched again and replaced the current publication | Fetched again and rebuilt the navigator |

Both native shortcuts were added to avoid reloading the open publication (Android 0806da6c, iOS 9ce3eae4). No caller needs a reload on re-open.

## Decision

- `openPublication` with the URL of the open publication returns the open publication without reloading it.
- To get a fresh instance, call `closePublication()` first.
- `loadPublication` never affects the open publication. It may parse a separate copy, or reuse the open one read-only, but it never closes or replaces it.

The Dart API doc comments and [`docs/api-reference/flutter-readium.md`](../api-reference/flutter-readium.md) state this contract.

## Consequences

- Android parses a separate copy when `loadPublication` hits the open URL, so a bookshelf load costs one extra parse of that book.
- Web keeps the open publication's URL so a re-open can return it; `closePublication()` forgets it.
- Re-opening returns the same publication instance, so state tied to it survives. An app that wants a clean instance must close first.

## Alternatives

Reloading on every `openPublication` gives fresh resources without an explicit close, but drops playback and reader state on every re-open, and no caller asked for it. Making `loadPublication` open the publication, as web did, conflates reading a manifest with choosing what the reader shows.
