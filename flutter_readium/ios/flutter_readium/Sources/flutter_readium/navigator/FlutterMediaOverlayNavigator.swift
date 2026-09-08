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
  internal var lastMediaOverlayItem: FlutterMediaOverlayItem? = nil
  
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
    
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    self._initialLocator = self.mapTextLocatorToMediaOverlayAudioLocator(initialLocator)
  }
  
  public override func initNavigator() async throws -> Void {
    Log.navigator.info("Initializing MediaOverlayNavigator")
    
    let mediaOverlays = await publication.getSyncNarrationMediaOverlays()
    
    guard let mediaOverlays = mediaOverlays else {
      Log.navigator.error("Failed to get mediaOverlays for sync-narration book." +
                          "isGuided? \(self.publication.containsGuidedNavigationMediaOverlays)")
      return
    }
    
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
    
    guard !audioReadingOrder.isEmpty else {
      Log.navigator.error("initNavigator() — audio readingOrder is empty; cannot initialize AudioNavigator.")
      return
    }
    
    // Copy the manifest and set its readingOrder to audioReadingOrder.
    var audioPubManifest = publication.manifest // var of struct == implicit copy
    audioPubManifest.readingOrder = audioReadingOrder
    audioPubManifest.metadata.conformsTo = [Publication.Profile.audiobook]
    
    // Note: This modifies the Publication reference !!!
    // For now caller must re-load the Publication from same URL, to get a separate reference.
    publication.manifest = audioPubManifest
    
    Log.navigator.info("New audio readingOrder found: \(audioReadingOrder)")
    // Save the media-overlays for later position matching.
    self.mediaOverlays = mediaOverlays
    
    try await super.initNavigator()
  }
  
  public override func play(fromLocator: Locator?) async {
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    let audioFromLocator = mapTextLocatorToMediaOverlayAudioLocator(fromLocator)
    await super.play(fromLocator: audioFromLocator ?? initialLocator)
  }
  
  public override func seek(toLocator: Locator) async -> Bool {
    guard let navigator = _audioNavigator,
          let audioLocator = mapTextLocatorToMediaOverlayAudioLocator(toLocator) else {
      Log.navigator.warn("seekToLocator - Could not map to an Audio Locator for: \(toLocator)")
      return false
    }
    let wasPlaying = navigator.state == .playing || navigator.state == .loading
    let navigated = await goBounded(to: audioLocator)
    // Go will sometimes result in a pause, if buffering was necessary.
    // So we actively ensure we resume playing (if we were before).
    if (wasPlaying) {
      navigator.play()
    }
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
    if let locator = location,
       let mediaOverlayItem = mediaOverlayItemFromAudioLocator(locator),
       let combinedLocator = mediaOverlayItem.toCombinedLocator(fromAudioLocator: locator) {
      timebasedState.currentLocator = combinedLocator
    }
    
    /// If state has changed, submit it to listener.
    if (timebasedState != self._lastTimebasedPlayerState) {
      self._lastTimebasedPlayerState = timebasedState
      self.listener?.timebasedNavigator(self, didChangeState: timebasedState)
    } else {
      Log.navigator.debug("Skipped state emission - duplicate")
    }
  }
  
  internal func mapTextLocatorToMediaOverlayAudioLocator(_ textLocator: Locator?) -> Locator? {
    guard let textLocator = textLocator else {
      Log.navigator.debug("mapTextLocatorToMediaOverlayAudioLocator - nil text locator")
      return nil
    }
    guard let matchingMediaOverlayItem = self.mediaOverlays.firstMap({ $0.itemFromLocator(textLocator) }),
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
