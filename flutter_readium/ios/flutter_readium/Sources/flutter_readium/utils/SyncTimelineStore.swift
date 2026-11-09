//
//  SyncTimelineStore.swift
//  flutter_readium
//
//  Lazy media-overlay timeline (iOS mirror of web `mediaoverlay/syncTimeline.ts`).
//

import Foundation
import ReadiumShared

/// Sliding window over the reading order for sync-narration / guided-navigation
/// timelines.
///
/// Startup loads only the segment (one alternate JSON) covering the initial
/// position; the rest is discovered ahead of playback, one segment at a time.
/// Which JSON belongs to reading-order item i comes from the manifest alone
/// (`resolvedSegments`, no fetch), and for Sync Narration the RO item's href IS
/// the cue text file, so a text href maps to its segment in O(1).
///
/// Guided Navigation strategy 1 (single publication-level document) is one fetch
/// total and is NOT streamed — `forPublication` returns nil for it and callers
/// keep the eager parse path.
///
/// The text reading order is snapshotted at construction: the media-overlay
/// navigator replaces `publication.manifest.readingOrder` with the audio window,
/// so live lookups against the publication would break mid-playback.
final class SyncTimelineStore {
  enum Kind {
    case syncNarration
    case guidedNavigation
  }

  /// Reading-order segments kept loaded ahead of the playhead.
  static let lookaheadSegments = 3
  /// Consecutive fetch/parse failures after which a segment is skipped.
  private static let maxSegmentFailures = 2

  private static let syncNarrationMediaType = MediaType("application/vnd.syncnarr+json")!
  private static let guidedNavigationMediaType = MediaType("application/guided-navigation+json")!

  private let publication: Publication
  private let kind: Kind
  private let toc: [Link]
  private let readingOrderLinks: [Link]

  /// roIndex -> resolved alternate link, derived from the manifest only.
  private let resolvedSegments: [Int: Link]
  /// roIndex -> parsed overlays (empty = covered by a shared document already loaded).
  private var loaded: [Int: [FlutterMediaOverlay]] = [:]
  /// resolved alternate href -> consecutive fetch/parse failures.
  private var failures: [String: Int] = [:]
  private var disposed = false

  private init(publication: Publication, kind: Kind, resolvedSegments: [Int: Link]) {
    self.publication = publication
    self.kind = kind
    self.toc = publication.getFlattenedToC()
    self.readingOrderLinks = publication.readingOrder
    self.resolvedSegments = resolvedSegments
  }

  /// Builds a store over the publication's per-reading-order alternates, or nil
  /// when streaming does not apply (GN strategy 1, or no alternates at all — the
  /// latter keeps the eager-parser contract).
  static func forPublication(_ publication: Publication, kind: Kind) -> SyncTimelineStore? {
    if kind == .guidedNavigation,
       !publication.links.filterByMediaType(guidedNavigationMediaType).isEmpty {
      return nil  // Strategy 1: one document covers the whole book.
    }
    let mediaType = kind == .syncNarration ? syncNarrationMediaType : guidedNavigationMediaType
    var resolved: [Int: Link] = [:]
    for (index, roLink) in publication.readingOrder.enumerated() {
      guard let alternate = roLink.alternates.filterByMediaType(mediaType).first else { continue }
      let parameters = LinkTemplateResolver.parameters(for: roLink, sidecarLink: alternate)
      guard let link = resolvedTemplateLink(alternate, parameters: parameters) else { continue }
      resolved[index] = link
    }
    return resolved.isEmpty ? nil : SyncTimelineStore(
      publication: publication, kind: kind, resolvedSegments: resolved)
  }

  // MARK: - Positions

  /// RO indexes that declare an alternate, ascending.
  private func segmentIndexes() -> [Int] {
    resolvedSegments.keys.sorted()
  }

  func isLoaded(_ roIndex: Int) -> Bool {
    loaded[roIndex] != nil
  }

  /// First segment index >= `from` that is neither loaded nor exhausted.
  func nextLoadableSegment(from: Int) -> Int? {
    for index in segmentIndexes() where index >= from {
      guard let href = resolvedSegments[index]?.href else { continue }
      if loaded[index] == nil, (failures[href] ?? 0) < Self.maxSegmentFailures {
        return index
      }
    }
    return nil
  }

  /// Index of the segment covering `textHref`, nil when no RO item matches.
  func roIndexForText(_ textHref: String) -> Int? {
    let path = String(textHref.split(separator: "#", maxSplits: 1).first ?? "")
    return readingOrderLinks.firstIndex {
      String($0.href.split(separator: "#", maxSplits: 1).first ?? "") == path
    }
  }

  /// Segment carrying cues for `audioHref`, nil when unloaded/unknown.
  func roIndexForAudio(_ audioHref: String?) -> Int? {
    guard let audioHref else { return nil }
    for index in segmentIndexes() {
      guard let overlays = loaded[index], !overlays.isEmpty else { continue }
      if overlays.contains(where: { $0.items.contains { $0.audioFile == audioHref } }) {
        return index
      }
    }
    return nil
  }

  /// Segment of the playhead, for the lookahead budget: the current audio track's
  /// segment, falling back to the loaded tail when its cues aren't known.
  func playheadSegmentIndex(audioHref: String?) -> Int {
    roIndexForAudio(audioHref) ?? max(loadedTailIndex(), 0)
  }

  /// Closest declared segment at or before `roIndex`: a deep link into a
  /// narration-less RO item starts at the segment that actually covers it.
  func nearestSegmentIndex(_ roIndex: Int) -> Int {
    let indexes = segmentIndexes()
    guard !indexes.isEmpty else { return roIndex }
    if indexes.contains(roIndex) { return roIndex }
    return indexes.last(where: { $0 <= roIndex }) ?? indexes[0]
  }

  /// Highest loaded segment index, or -1.
  func loadedTailIndex() -> Int {
    loaded.keys.filter { loaded[$0]?.isEmpty == false }.max() ?? -1
  }

  /// Highest RO index that declares an alternate, or -1.
  func lastSegmentIndex() -> Int {
    resolvedSegments.keys.max() ?? -1
  }

  // MARK: - Loading

  /// Fetch + parse one alternate; cached and failure-counted.
  /// shortcut: no in-flight de-dupe, callers serialize loads (single lookahead
  /// task + seek path); a race costs one duplicate fetch, never a wrong result.
  @discardableResult
  func loadSegment(roIndex: Int) async -> [FlutterMediaOverlay]? {
    guard let link = resolvedSegments[roIndex] else { return nil }
    if let cached = loaded[roIndex] { return cached }  // empty = covered by shared doc
    let href = link.href
    if (failures[href] ?? 0) >= Self.maxSegmentFailures { return nil }

    let overlays = await fetchSegment(roIndex: roIndex, link: link)
    if let overlays {
      // A shared document (GN dedupe) satisfies every RO index pointing at it,
      // but its overlays count once: keep them on the requesting index only and
      // mark the siblings loaded-but-empty so nothing re-fetches them.
      for index in resolvedSegments.keys
      where index != roIndex && resolvedSegments[index]?.href == href && loaded[index] == nil {
        loaded[index] = []
      }
      loaded[roIndex] = overlays
    } else {
      failures[href] = (failures[href] ?? 0) + 1
      Log.readium.warn("Failed to fetch/parse media-overlay segment \(roIndex) (\(href))")
    }
    return overlays
  }

  /// Loads the segment covering `textHref`. True when its cues are available.
  @discardableResult
  func ensureSegmentForText(_ textHref: String) async -> Bool {
    guard let roIndex = roIndexForText(textHref) else { return false }
    // Loaded-but-empty marks a shared document already covering this index.
    if isLoaded(roIndex) { return true }
    return await loadSegment(roIndex: roIndex) != nil
  }

  /// All parsed overlays, ordered by reading-order segment.
  func overlays() -> [FlutterMediaOverlay] {
    segmentIndexes().flatMap { loaded[$0] ?? [] }
  }

  /// Loads the segment at `roIndex`; the caller falls back to the eager parser
  /// when it yields nothing.
  func loadWindow(at roIndex: Int) async -> [FlutterMediaOverlay] {
    await loadSegment(roIndex: roIndex)
    return overlays()
  }

  /// Ensure the next `lookaheadSegments` segment *slots* ahead of `roIndex` are
  /// loaded. The budget is position-bound (which slots), not load-count-bound:
  /// counting loaded segments anywhere ahead would let the old forward window
  /// eat the budget after a backward jump — playback would then skip into that
  /// window — and one flaky pass would burn the whole budget and concede an end
  /// of book while segments are still loadable (ADR 0003 "honest end"). A
  /// failed load stays in its slot and is retried until it loads or hits
  /// `maxSegmentFailures`, whichever comes first.
  func fillAhead(from roIndex: Int) async {
    let ahead = segmentIndexes().filter { $0 > roIndex }.prefix(Self.lookaheadSegments)
    for i in ahead {
      if disposed { return }
      while loaded[i] == nil,
            (failures[resolvedSegments[i]!.href] ?? 0) < Self.maxSegmentFailures {
        await loadSegment(roIndex: i)
      }
    }
  }

  /// Stop background lookahead after the owning session is disposed.
  func cancelPending() {
    disposed = true
  }

  // MARK: - Durations

  /// Book-wide total duration in seconds without fetching anything: declared
  /// `metadata.duration`, else the sum of the RO items' declared durations
  /// (nil when any is missing — window-relative totals that grow per extension
  /// are the accepted fallback).
  func totalDurationSecs() -> TimeInterval? {
    if let declared = publication.metadata.duration, declared > 0 { return declared }
    let durations = readingOrderLinks.map { $0.duration }
    guard !durations.isEmpty, durations.allSatisfy({ ($0 ?? 0) > 0 }) else { return nil }
    return durations.reduce(0) { $0 + $1! }
  }

  /// Sum of durations of the segments before `roIndex`; nil when any preceding
  /// segment is unloaded and undeclared.
  private func cumulativeBefore(_ roIndex: Int) -> TimeInterval? {
    var sum: TimeInterval = 0
    for index in 0..<roIndex {
      guard resolvedSegments[index] != nil else { continue }
      guard let duration = segmentDurationSecs(
        declared: readingOrderLinks[index].duration, overlays: loaded[index]) else {
        return nil
      }
      sum += duration
    }
    return sum
  }

  /// Declared duration when present, else cue-sum of the segment's overlays.
  private func segmentDurationSecs(
    declared: TimeInterval?, overlays: [FlutterMediaOverlay]?
  ) -> TimeInterval? {
    if let declared, declared > 0 { return declared }
    guard let overlays else { return nil }
    let cueSum = overlays.flatMap(\.items).reduce(0) { sum, item in
      guard let start = item.audioStart, let end = item.audioEnd, end > start else { return sum }
      return sum + (end - start)
    }
    return cueSum > 0 ? cueSum : nil
  }

  /// Book-wide progression for an audio locator; nil while the book total or the
  /// segments before the playhead are still unknown.
  func locatorProgression(for audioLocator: Locator) -> Double? {
    guard let total = totalDurationSecs(), total > 0,
          let roIndex = roIndexForAudio(audioLocator.href.string),
          let before = cumulativeBefore(roIndex) else {
      return nil
    }
    return min(1, max(0, (before + (audioLocator.timeOffset ?? 0)) / total))
  }

  // MARK: - Parsing

  /// Fetches and parses exactly one alternate document.
  private func fetchSegment(roIndex: Int, link: Link) async -> [FlutterMediaOverlay]? {
    guard let json = try? await publication.get(link)?.read().asJSONObject().get() else {
      return nil
    }
    let declaredDuration = readingOrderLinks.indices.contains(roIndex)
      ? readingOrderLinks[roIndex].duration : nil
    switch kind {
    case .syncNarration:
      guard let overlay = FlutterMediaOverlay.fromJson(
        json,
        atPosition: roIndex,
        atTocHref: nil,
        readingOrderDuration: declaredDuration,
        tocHrefs: toc.map { $0.href }
      ), !overlay.items.isEmpty else {
        return nil
      }
      // ToC title enrichment runs per loaded window, as the eager path does per overlay.
      return [overlay.withTocTitles(toc)]
    case .guidedNavigation:
      guard let document = GuidedNavigationDocument.fromJson(json) else { return nil }
      let positioned = document.toMediaOverlays().compactMap { overlay -> FlutterMediaOverlay? in
        guard let textFile = overlay.textFile else { return nil }
        let roEntry = readingOrderLinks.enumerated().first {
          $1.href.split(separator: "#", maxSplits: 1).first.map(String.init) == textFile
        }
        let duration = roEntry?.element.duration
        let items = overlay.items.map { item in
          FlutterMediaOverlayItem(
            audio: item.audio, text: item.text, position: roEntry?.offset ?? 0,
            readingOrderDuration: duration)
        }
        return FlutterMediaOverlay(items: items, readingOrderDuration: duration, narrationContainerTocHrefs: overlay.narrationContainerTocHrefs)
      }
      guard !positioned.isEmpty else { return nil }
      // Sliding-window ToC enrichment per segment: a chapter spanning two
      // documents can miss cross-boundary title inheritance (accepted — playback
      // never depends on tocTitle).
      return publication.enrichOverlaysWithToc(positioned)
    }
  }
}
