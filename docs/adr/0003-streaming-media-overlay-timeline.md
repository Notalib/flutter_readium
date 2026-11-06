# ADR 0003: Streaming media-overlay timeline

- **Status:** Accepted
- **Date:** 2026-11-06
- **Scope:** Sync Narration and Guided Navigation cue loading on iOS, Android, and web
- **Implementation:** `SyncTimelineStore` (`web/src/mediaoverlay/syncTimeline.ts`, `ios/.../utils/SyncTimelineStore.swift`, `android/.../SyncTimelineStore.kt`) and the per-platform media-overlay navigator that consumes it

## Context

Media-overlay playback previously resolved every segment's narration JSON when the session started, then built one audio manifest for the whole book. For a long Sync Narration publication that is one HTTP fetch per chapter before the first sound plays, and a resident cue list for the entire book, even though a listener only ever needs the segment under the playhead plus a little ahead.

The upstream audio navigators (swift-toolkit `AVPlayer`, kotlin-toolkit `ExoPlayer`, `@readium/navigator` on web) construct their playable list from the publication's audio reading order at build time. None exposes a supported "append the next audio track" operation. That constraint shapes every option below.

## Decision

Resolve the segment layout from the manifest only, and load narration JSON lazily in a sliding window around the playhead.

- **Start from one fetch.** At enable, load only the segment covering the start position and build the audio manifest from that window. The segment layout (hrefs, durations, order) comes from the publication manifest, not from the narration JSONs, so the window can be planned without fetching bodies.
- **Window:** keep up to `LOOKAHEAD_SEGMENTS = 3` segments ahead of the playhead loaded, extending when less than `LOOKAHEAD_MARGIN_SECONDS = 60` remain on the last loaded track. A per-segment failure cap (`MAX_SEGMENT_FAILURES = 2`) bounds retries; a segment that exhausts it is treated as not loadable.
- **Extend by teardown and rebuild.** When new audio tracks enter the window, tear the upstream navigator down and rebuild it at the current audio locator with the enlarged manifest. Rebuilding — rather than a live append — is forced by the upstream build-time playlist constraint.
- **Seek loads the target first.** A jump into a not-yet-loaded segment runs a bounded ensure-window loop that fetches the covering segment (plus its ahead budget from the playhead) and rebuilds before the seek is applied, so navigation reaches the last chapter as easily as the first.
- **Honest end.** Report `.ended` only when nothing loadable remains past the window. A gap that is still within the failure cap is awaited, not declared as the end of the book.
- **Book-wide totals.** Player position is window-relative once the window slides; the store supplies publication-wide `totalProgression` and `totalDuration` for every reported locator.

Eager whole-book loading stays on the path whenever the store is unavailable or its initial window is empty, for Guided Navigation strategy 1 (a single narration document — laziness buys nothing), and for restoring playback after process death.

## Consequences and limits

- **Window slides forward past earlier chapters.** After a forward jump the outgoing navigator briefly reports a track the new window no longer holds. In media-overlay mode `currentLocator` is contractually a *text* locator, so an audio locator that maps to no loaded cue must never leak as `currentLocator`; the platforms emit a null locator there and the rebuilt navigator re-reports the position.
- **Lookahead runs only while playing.** A paused tick must not trigger a rebuild: rebuilds resume at the old position and would race a paused seek. Reaching the loaded tail while paused is covered by the edge-takeover path, not by the lookahead.
- **A rebuild is audible as a hiccup** on window extension. This is the accepted cost of single-fetch startup; it is bounded to one rebuild per newly-arrived track and only while playing.
- The window/margin/failure constants are identical across the three platforms but are tuning values, not contract; they may diverge per platform if device evidence calls for it.

## Alternatives

Loading the whole book up front is simpler and needs no rebuild, but pays a fetch-per-chapter at start and keeps every cue resident; that is the behavior this replaces. Appending tracks to a live navigator would avoid the rebuild, but the upstream toolkits offer no supported append path. Loading on demand with no ahead window (exactly one segment live) removes the rebuild during continuous playback but breaks down at every track boundary, since the next track is not in the manifest when the current one ends; the 3-ahead window is what lets a boundary be crossed inside the already-built manifest.
