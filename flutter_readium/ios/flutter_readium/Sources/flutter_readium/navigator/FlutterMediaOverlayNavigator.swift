//
//  FlutterMediaOverlayNavigator.swift
//  Pods
//
//  Created by Daniel Dam Freiling on 29/10/2025.
//

import Foundation
import ReadiumShared
import ReadiumNavigator

public class FlutterMediaOverlayNavigator : FlutterAudioNavigator
{
  internal var mediaOverlays: [FlutterMediaOverlay] = []
  /// Streaming timeline store, nil on the eager path (GN strategy 1, no alternates,
  /// or the initial segment yielded no cues).
  private var store: SyncTimelineStore?
  private var pendingTextInitialLocator: Locator?
  /// Parsed XHTML per resource path, for seeks to ToC containers absent from the narration.
  private var xhtmlIdTrees: [String: XhtmlIdTree?] = [:]
  
  public override var currentLocator: Locator? {
    get {
      if let audioLocator = audioLocator,
         let mediaOverlayItem = mediaOverlayItemFromAudioLocator(audioLocator),
         let combinedLocator = mediaOverlayItem.toCombinedLocator(fromAudioLocator: audioLocator) {
        return combinedLocator
      } else {
        return audioLocator
      }
    }
  }
  
  public override init(publication: Publication, preferences: FlutterAudioPreferences, initialLocator: Locator?) {
    super.init(publication: publication, preferences: preferences, initialLocator: initialLocator)
    
    // The overlays load in `initNavigator()`, so the Text-based locator is mapped there. The raw
    // locator is kept because `super.init` resolves it to a time-only locator, dropping the text id.
    self.pendingTextInitialLocator = initialLocator
    self._initialLocator = nil
  }
  
  public override func initNavigator() async throws -> Void {
    Log.navigator.info("Initializing MediaOverlayNavigator")

    let kind: SyncTimelineStore.Kind = publication.containsGuidedNavigationMediaOverlays
      ? .guidedNavigation : .syncNarration
    let timeline = SyncTimelineStore.forPublication(publication, kind: kind)
    var mediaOverlays: [FlutterMediaOverlay]?
    if let timeline {
      // Startup cost: the single alternate covering the initial position.
      let requested = pendingTextInitialLocator.flatMap { timeline.roIndexForText($0.href.string) } ?? 0
      mediaOverlays = await timeline.loadWindow(at: timeline.nearestSegmentIndex(requested))
      if mediaOverlays?.isEmpty ?? true {
        Log.navigator.warn("Streaming timeline produced no cues for \(kind); falling back to eager parse")
        timeline.cancelPending()
        self.store = nil
      } else {
        self.store = timeline
      }
    }

    if self.store == nil {
      mediaOverlays = await publication.getSyncNarrationMediaOverlays()
    }

    guard var mediaOverlays = mediaOverlays else {
      Log.navigator.error("Failed to get mediaOverlays for sync-narration book." +
                          "isGuided? \(self.publication.containsGuidedNavigationMediaOverlays)")
      return
    }

    // ToC ownership is resolved per loaded window.
    mediaOverlays = await resolveTocBoundaries(mediaOverlays)

    guard applyAudioWindow(mediaOverlays) else {
      Log.navigator.error("initNavigator() — audio readingOrder is empty; cannot initialize AudioNavigator.")
      return
    }

    applyMediaOverlays(mediaOverlays)
    if let pending = pendingTextInitialLocator {
      _initialLocator = mapTextLocatorToMediaOverlayAudioLocator(await anchorUncuedTextLocator(pending))
      pendingTextInitialLocator = nil
    }

    try await super.initNavigator()
  }

  /// Replaces the publication's reading order with the audio files of the loaded
  /// window (one Link per overlay carrying audio, in reading-order).
  ///
  /// Note: This modifies the Publication reference !!!
  /// For now caller must re-load the Publication from same URL, to get a separate reference.
  @discardableResult
  private func applyAudioWindow(_ mediaOverlays: [FlutterMediaOverlay]) -> Bool {
    // Skip overlays with no items — a `narration` block with no valid audio/text pairs
    // yields an empty overlay, and force-unwrapping `.first` here would trap.
    let audioReadingOrder: [Link] = mediaOverlays.compactMap { narr in
      guard let item = narr.items.first else { return nil }
      return Link(
        href: item.audioFile,
        mediaType: item.audioMediaType,
        title: item.tocTitle,
        duration: narr.items.reduce(0) { $0 + ($1.audioDuration ?? 0) }
      )
    }
    guard !audioReadingOrder.isEmpty else { return false }

    var audioPubManifest = publication.manifest // var of struct == implicit copy
    audioPubManifest.readingOrder = audioReadingOrder
    audioPubManifest.metadata.conformsTo = [Publication.Profile.audiobook]
    publication.manifest = audioPubManifest

    Log.navigator.info("New audio readingOrder found: \(audioReadingOrder)")
    return true
  }
  
  internal func resolveTocBoundaries(_ overlays: [FlutterMediaOverlay]) async -> [FlutterMediaOverlay] {
    // The audio window replaces the text reading order, so `containsSyncNarration`
    // goes false after the first window; a live store keeps enrichment running.
    guard publication.containsSyncNarration || store != nil else { return overlays }
    let toc = publication.getFlattenedToC()
    var trees: [String: XhtmlIdTree] = [:]
    let items = overlays.flatMap(\.items)
    let represented = Set(items.flatMap { [$0.text, $0.tocHref].compactMap { $0 } }).union(overlays.flatMap { $0.narrationContainerTocHrefs })
    let boundaries = toc.filter { !represented.contains($0.href) }
    for href in Set(items.filter { $0.tocHref != nil }.map(\.textFile)).sorted() {
      if boundaries.contains(where: { $0.href.hasPrefix(href + "#") }),
         let tree = await xhtmlIdTree(href: href) {
        trees[href] = tree
      }
    }
    // Resolve ownership before initial mapping and owner-based navigation use the items.
    return overlays.map { $0.withTocBoundaries(boundaries, trees: trees) }
  }

  /// Saves the media-overlays for later position matching, and maps the pending initial locator.
  internal func applyMediaOverlays(_ mediaOverlays: [FlutterMediaOverlay]) {
    self.mediaOverlays = mediaOverlays
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    self._initialLocator = mapTextLocatorToMediaOverlayAudioLocator(pendingTextInitialLocator)
  }
  
  public override func play(fromLocator: Locator?) async {
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    var anchored = fromLocator
    if let fromLocator {
      await ensureWindowForSeek(textHref: fromLocator.href.string)
      anchored = await anchorUncuedTextLocator(fromLocator)
    }
    if fromLocator != nil && anchored == nil {
      settlePendingEdgeTakeover(seekSucceeded: false)
      return
    }
    let audioFromLocator = mapTextLocatorToMediaOverlayAudioLocator(anchored)
    if fromLocator != nil && audioFromLocator == nil {
      settlePendingEdgeTakeover(seekSucceeded: false)
      return
    }
    await super.play(fromLocator: audioFromLocator ?? initialLocator)
    if fromLocator != nil { settlePendingEdgeTakeover(seekSucceeded: true) }
  }
  
  public override func seek(toLocator: Locator) async -> Bool {
    // A seek beyond the loaded window needs that segment's cues + audio track first.
    await ensureWindowForSeek(textHref: toLocator.href.string)
    let toLocator = await anchorUncuedTextLocator(toLocator)
    guard let navigator = _audioNavigator,
          let audioLocator = mapTextLocatorToMediaOverlayAudioLocator(toLocator) else {
      Log.navigator.warn("seekToLocator - Could not map to an Audio Locator for: \(toLocator)")
      settlePendingEdgeTakeover(seekSucceeded: false)
      return false
    }
    let wasPlaying = navigator.state == .playing || navigator.state == .loading
    let navigated = await goBounded(to: audioLocator)
    // Go will sometimes result in a pause, if buffering was necessary.
    // So we actively ensure we resume playing (if we were before).
    if (wasPlaying) {
      navigator.play()
    }
    settlePendingEdgeTakeover(seekSucceeded: navigated)
    return navigated
  }
  
  public override func seek(toProgression: Double) async -> Bool {
    guard let navigator = _audioNavigator,
          let locator = audioLocator?.copyWithProgressionLocations(progression: toProgression) else {
      Log.navigator.warn("seekToProgression - Could not setup locator with progression: \(toProgression)")
      return false
    }
    let wasPlaying = navigator.state == .playing || navigator.state == .loading
    let navigated = await goBounded(to: locator)
    // Go will sometimes result in a pause, if buffering was necessary.
    // So we actively ensure we resume playing (if we were before).
    if (wasPlaying) {
      navigator.play()
    }
    return navigated
  }
  
  public override func decorationsUpdated() -> Void {
    if let audioLocator = audioLocator,
       let mediaOverlayItem = mediaOverlayItemFromAudioLocator(audioLocator),
       let textLocator = mediaOverlayItem.asTextLocator {
      self.listener?.timebasedNavigator(self, requestsHighlightAt: textLocator, withWordLocator: nil)
    } else {
      Log.navigator.warn("Could not update decorations, no current Locator")
    }
  }

  // MARK: - Streaming window

  /// Rebuild the window when less than this many seconds remain on the last known track.
  private static let lookaheadMarginSecs: TimeInterval = 60

  /// True while a window extension (lookahead, edge takeover or seek) is running;
  /// also the single-in-flight guard.
  private var windowBusy = false
  /// The running window extension, so a seek can await it instead of mapping
  /// against cues that are about to arrive.
  private var extensionInFlight: Task<Void, Never>?
  /// The last known track ended while an extension was loading.
  private var pendingEdgeTakeover = false

  /// Suppress the terminal `.ended` while more cue segments are loadable — the
  /// window extension rebuild continues playback (mirrors web `takeOverAtEdge`).
  /// False means honest end: nothing loadable remains, or every load failed.
  internal override func takesOverTimelineEdge(at info: MediaPlaybackInfo) -> Bool {
    guard let store, !_disposed else { return false }
    // Nothing loadable past the loaded window: honest end, today's behavior.
    guard store.nextLoadableSegment(from: store.loadedTailIndex() + 1) != nil else { return false }
    // Flag first: an extension already in flight must take the edge over too and
    // resume at its first new track instead of the ended one.
    pendingEdgeTakeover = true
    queueLookahead()
    return windowBusy
  }

  private func queueLookahead() {
    guard !windowBusy, store != nil, !_disposed else { return }
    windowBusy = true
    extensionInFlight = Task { @MainActor [weak self] in
      defer {
        self?.windowBusy = false
        self?.extensionInFlight = nil
      }
      await self?.extendWindow()
    }
  }

  /// Lookahead driver: called from the audio locator ticks, refreshes the window
  /// once less than the margin remains on the last known track. Only while
  /// actually playing — paused ticks must not churn the window (the web mapper
  /// driver only runs during playback), and rebuilds while paused race paused
  /// seeks. The edge-takeover path covers a playhead that reaches the tail.
  private func maybeExtendWindow(at audioLocator: Locator) {
    guard let store, !windowBusy, !_disposed, playback.state == .playing else { return }
    guard store.nextLoadableSegment(from: store.loadedTailIndex() + 1) != nil else { return }
    // `playback` is the info published by the upstream time observer; reading
    // `playbackInfo` here would do a synchronous AVPlayer read on every tick.
    guard let duration = playback.duration, duration > 0 else { return }
    let remaining = duration - (audioLocator.timeOffset ?? playback.time)
    guard remaining < Self.lookaheadMarginSecs else { return }
    queueLookahead()
  }

  /// Loads the segment covering a sought text href, then rebuilds the audio
  /// manifest + navigator so the target track is playable. The caller maps and
  /// seeks against the extended cues afterwards.
  ///
  /// Bounded loop: a short (<60 s) track makes the locator-tick lookahead fire
  /// again right after each rebuild, and those extensions resume at the OLD
  /// position — awaiting a single in-flight task would let the following seek
  /// land on the about-to-be-replaced navigator (no position report while
  /// paused). Each pass joins any in-flight extension, fetches the target, and
  /// extends under the exclusive slot; a pass that lands nothing new returns.
  private func ensureWindowForSeek(textHref: String) async {
    guard store != nil, !_disposed else { return }
    for attempt in 0..<3 {
      await extensionInFlight?.value
      if windowBusy {
        continue // joined an extension; re-check on the next pass
      }
      guard let store, !_disposed else { return }
      guard store.roIndexForText(textHref) != nil else { return }
      windowBusy = true
      await store.ensureSegmentForText(textHref)
      await store.fillAhead(from: store.playheadSegmentIndex(audioHref: audioLocator?.href.string))
      let grew = hasNewAudioTrack(loadedBefore: mediaOverlays)
        || store.overlays().flatMap(\.items).count > mediaOverlays.flatMap(\.items).count
      if grew {
        await applyWindowExtension(resumeAt: audioLocator)
      }
      windowBusy = false
      if !grew || attempt == 2 { return }
    }
  }

  /// Settle a deferred end-of-window edge that a seek superseded or stranded.
  /// The flag is set when the last loaded track ended while the seek's window
  /// work held the extension slot; a successful seek relocated the playhead, so
  /// resuming at the first new track is obsolete — clear it. A failed seek left
  /// the player on the ended track: run the deferred takeover now, or report the
  /// honest end when nothing loadable remains, instead of letting the stale flag
  /// fire mid-playback on a later extension.
  private func settlePendingEdgeTakeover(seekSucceeded: Bool) {
    guard pendingEdgeTakeover, !_disposed else { return }
    if seekSucceeded {
      pendingEdgeTakeover = false
      return
    }
    guard let store, store.nextLoadableSegment(from: store.loadedTailIndex() + 1) != nil else {
      pendingEdgeTakeover = false
      submitPublicationEnded(info: playback)
      return
    }
    queueLookahead()
  }

  /// Background lookahead: fill the window ahead of the playhead, rebuild when
  /// new audio tracks appeared.
  @MainActor
  private func extendWindow() async {
    guard let store, !_disposed else { return }
    // Budget from the PLAYHEAD's segment, not the loaded tail: after a seek-back
    // the tail sits ahead and would starve the K budget down to zero.
    await store.fillAhead(from: store.playheadSegmentIndex(audioHref: audioLocator?.href.string))
    if hasNewAudioTrack(loadedBefore: mediaOverlays) {
      await applyWindowExtension(resumeAt: audioLocator)
      return
    }
    // Nothing new landed: if `.ended` was held back, report it honestly now.
    if pendingEdgeTakeover {
      pendingEdgeTakeover = false
      submitPublicationEnded(info: playback)
    }
  }

  /// Re-applies the merged overlay list, re-derives the audio window manifest and
  /// rebuilds the upstream navigator at `resumeAt`.
  private func applyWindowExtension(resumeAt: Locator?) async {
    guard let store else { return }
    var extended = store.overlays()
    guard !extended.isEmpty else { return }
    let previous = mediaOverlays
    let takeover = pendingEdgeTakeover
    pendingEdgeTakeover = false
    extended = await resolveTocBoundaries(extended)
    let newTrack = hasNewAudioTrack(loadedBefore: previous)
    // Cues are live from here on; `_initialLocator` keeps its initial mapping.
    mediaOverlays = extended
    // Only a new audio file needs a new playlist; extra cues for tracks already
    // in the window are picked up by the lookups without a rebuild hiccup.
    guard newTrack || takeover else { return }
    guard applyAudioWindow(extended) else { return }
    let target = takeover ? firstNewTrackLocator(loadedBefore: previous) ?? resumeAt : resumeAt
    Log.navigator.info("Extending media-overlay window to \(extended.count) overlay(s); rebuilding at \(target?.href.string ?? "(initial)")")
    // `rebuildNavigator` resumes playback; a refresh while paused must stay paused.
    let wasPlaying = _audioNavigator?.state == .playing || _audioNavigator?.state == .loading
    await rebuildNavigator(at: target ?? resumeAt)
    if !wasPlaying {
      await pause()
    }
  }

  /// True when the loaded overlays gained an audio file the old window lacked.
  private func hasNewAudioTrack(loadedBefore: [FlutterMediaOverlay]) -> Bool {
    guard let store else { return false }
    let known = Set(loadedBefore.compactMap(\.audioFile))
    return store.overlays().compactMap(\.audioFile).contains { !known.contains($0) }
  }

  /// Start of the first audio track the previous window didn't have — the resume
  /// point when the last known track ended while its successor was loading.
  private func firstNewTrackLocator(loadedBefore: [FlutterMediaOverlay]) -> Locator? {
    let known = Set(loadedBefore.compactMap(\.audioFile))
    for overlay in mediaOverlays {
      guard let audio = overlay.audioFile, !known.contains(audio),
            let locator = overlay.items.first?.asAudioLocator else { continue }
      return locator
    }
    return nil
  }

  /// Publication-wide totals: the audio manifest only covers the loaded window,
  /// so the store supplies book-wide progression/duration when it knows them.
  private func applyTimelineTotals(to state: ReadiumTimebasedState, audioLocator: Locator?) {
    guard let store, let audioLocator,
          let progression = store.locatorProgression(for: audioLocator) else { return }
    state.currentLocator?.locations.totalProgression = progression
    state.totalDuration = store.totalDurationSecs() ?? state.totalDuration
    state.totalProgressDuration = computeTotalProgressDuration(
      totalProgression: progression, publicationDuration: state.totalDuration)
  }

  public override func dispose() -> Void {
    store?.cancelPending()
    store = nil
    super.dispose()
  }
  
  private func mediaOverlayItemFromAudioLocator(_ audioLocator: Locator) -> FlutterMediaOverlayItem? {
    if let timeOffset = MediaTimeFragment.seconds(from: audioLocator.locations.fragments),
       let mediaOverlay = mediaOverlays.first(where: { $0.itemInRangeOfTime(timeOffset, inHref:  audioLocator.href.string) }) {
      return mediaOverlay
    } else {
      Log.navigator.warn("Could not find MediaOverlay from Audio Locator: \(audioLocator)")
      return nil
    }
  }
  
  internal var lastTextSyncKey: String?
  
  internal override func submitAudioLocatorReachedToListener(_ location: Locator) {
    maybeExtendWindow(at: location)
    /// Map Audio-based Locator to a Text-based Locator, before submitting to viewer.
    if let mediaOverlayItem = mediaOverlayItemFromAudioLocator(location),
       let textLocator = mediaOverlayItem.asTextLocator {
      
      let syncKey = textLocator.href.string + (textLocator.locations.cssSelector ?? "")
      if syncKey != lastTextSyncKey {
        lastTextSyncKey = syncKey
        self.listener?.timebasedNavigator(self, reachedLocator: textLocator, segmentDuration: mediaOverlayItem.audioDuration, isWordRange: false)
      }
      
      self.listener?.timebasedNavigator(self, requestsHighlightAt: textLocator, withWordLocator: nil)
    } else {
      Log.navigator.warn("Did not find MediaOverlay matching audio Locator: \(location)")
    }
  }
  
  internal override func submitTimebasedPlayerStateToListener(info: MediaPlaybackInfo, location: Locator?, bufferedInterval: TimeInterval? = nil) {
    
    /// Create TimebasedState and send it over the timebased-state stream.
    let timebasedState = mapToTimebasedState(info: info, location: location, bufferedInterval: bufferedInterval)
    
    /// Map audio Locator to a combined Text-based Locator, before submitting to listener.
    /// In media-overlay mode `currentLocator` is contractually a text locator; the base
    /// map falls back to the raw audio locator, which must never leak when the playhead
    /// briefly sits on a track the slid window no longer contains (e.g. the old resume
    /// position right after a paused cross-chapter jump rebuilds the navigator).
    if let locator = location,
       let mediaOverlayItem = mediaOverlayItemFromAudioLocator(locator),
       let combinedLocator = mediaOverlayItem.toCombinedLocator(fromAudioLocator: locator) {
      timebasedState.currentLocator = combinedLocator
      applyTimelineTotals(to: timebasedState, audioLocator: locator)
    } else {
      timebasedState.currentLocator = nil
    }
    
    /// If state has changed, submit it to listener.
    if (timebasedState != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = timebasedState
      self.listener?.timebasedNavigator(self, didChangeState: timebasedState)
    } else {
      Log.navigator.debug("Skipped state emission - duplicate")
    }
  }
  
  /// Resolve XHTML targets absent from the narration before applying same-file fallback guards.
  /// A cue-less heading can seek forward without becoming that cue's ToC owner. See ADR 0001.
  private func anchorUncuedTextLocator(_ locator: Locator) async -> Locator? {
    let href = locator.href.string
    guard let textId = locator.textId,
          !mediaOverlays.contains(where: {
            $0.itemFromTextId(textId, inHref: href) != nil || $0.itemFromTocHref(textId, inHref: href) != nil
          }) else {
      return locator
    }
    let cueIds = Set(mediaOverlays.flatMap(\.items).filter { $0.textFile == href }.map(\.textId))
    guard let tree = await xhtmlIdTree(href: locator.href.path) else { return locator }
    return tree.anchor(locator, textId: textId, cueIds: cueIds)
  }

  private func xhtmlIdTree(href: String) async -> XhtmlIdTree? {
    if let cached = xhtmlIdTrees[href] {
      return cached
    }
    let tree = await publication.xhtmlIdTree(hrefRelativePath: href)
    xhtmlIdTrees[href] = .some(tree)
    return tree
  }

  internal func mapTextLocatorToMediaOverlayAudioLocator(_ textLocator: Locator?) -> Locator? {
    guard let textLocator = textLocator else {
      Log.navigator.debug("mapTextLocatorToMediaOverlayAudioLocator - nil text locator")
      return nil
    }
    // Only allow the imprecise resource-first fallback when tapping into a
    // *different* resource than the one currently playing — an uncued anchor
    // within the current chapter must not rewind audio. See issue #139.
    let currentTextFile = audioLocator.flatMap { mediaOverlayItemFromAudioLocator($0)?.textFile }
    let crossResource = currentTextFile == nil
      || currentTextFile != textLocator.href.string
    guard let matchingMediaOverlayItem = self.mediaOverlays.firstMap({ $0.itemFromLocator(textLocator, allowResourceFallback: crossResource) }),
          var audioLocator = matchingMediaOverlayItem.asAudioLocator else {
      Log.navigator.warn("mapTextLocatorToMediaOverlayAudioLocator - no media overlay matched text locator " +
                         "href=\(textLocator.href.string) mediaType=\(textLocator.mediaType.string) fragments=\(textLocator.locations.fragments)")
      return nil
    }
    
    // If progression is given, try to resolve that to a time offset.
    if let progression = textLocator.locations.progression,
       let duration = matchingMediaOverlayItem.readingOrderDuration {
      let timeOffset = progression * duration
      Log.navigator.debug("Used progression to calculate time offset: \(progression) progress => \(timeOffset) offset")
      audioLocator = audioLocator.copyWithOffset(timeOffset)
    }
    
    // If the input Text Locator, is a combined locator with a time fragment
    // we use this, as it can be more precise than the MediaOverlayItem fragment.
    if let textLocatorTime = textLocator.locations.time,
       let textLocatorTimeBegin = textLocatorTime.begin {
      Log.navigator.debug("TextLocator had more precise time offset: \(textLocatorTimeBegin)")
      let timeOffset = textLocatorTimeBegin
      audioLocator = audioLocator.copyWithOffset(timeOffset)
    }
    
    Log.navigator.debug("mapTextLocatorToMediaOverlayAudioLocator - mapped text href=\(textLocator.href.string) " +
                        "-> audio href=\(audioLocator.href.string) fragments=\(audioLocator.locations.fragments)")
    return audioLocator
  }
}
