//
//  FlutterMediaOverlayNavigator.swift
//  Pods
//
//  Created by Daniel Dam Freiling on 29/10/2025.
//

import ReadiumShared
import ReadiumNavigator

public class FlutterMediaOverlayNavigator : FlutterAudioNavigator
{
  internal let OTAG = "FlutterMediaOverlayNavigator"
  
  internal var mediaOverlays: [FlutterMediaOverlay] = []
  internal var lastMediaOverlayItem: FlutterMediaOverlayItem? = nil
  
  public override init(publication: Publication, preferences: FlutterAudioPreferences, initialLocator: Locator?) {
    super.init(publication: publication, preferences: preferences, initialLocator: initialLocator)
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    self._initialLocator = self.mapTextLocatorToMediaOverlayLocator(initialLocator)
  }

  public override func initNavigator() async -> Void {
    debugPrint("Publication with Synchronized Narration reading-order found!")
    let narrationLinks = publication.readingOrder.compactMap {
      var link = $0.alternates.filterByMediaType(MediaType("application/vnd.syncnarr+json")!).first
      link?.title = $0.title
      return link
    }
    let narrationJson = await narrationLinks.asyncCompactMap { try? await publication.get($0)?.readAsJSONObject().get() }
    let mediaOverlays = narrationJson.enumerated().compactMap({ idx, json in FlutterMediaOverlay.fromJson(json, atPosition: idx) })
    
    // Assert that we did not lose any MediaOverlays during JSON deserialization.
    assert(mediaOverlays.count == narrationLinks.count)
    
    let audioReadingOrder = mediaOverlays.enumerated().map { (idx, narr) in
      narrationLinks.getOrNil(idx).map {
        return Link(
          href: narr.items.first!.audioFile,
          mediaType: MediaType.mpegAudio,
          title: $0.title,
          duration: narr.items.reduce(0, { $0 + ($1.audioDuration ?? 0) })
        )
      }
    }.filter({ $0 != nil }) as! [Link]
    
    // Copy the manifest and set its readingOrder to audioReadingOrder.
    var audioPubManifest = publication.manifest // var of struct == implicit copy
    audioPubManifest.readingOrder = audioReadingOrder
    audioPubManifest.metadata.conformsTo = [Publication.Profile.audiobook]
    
    // TODO: This modifies the existing Publication reference !!!
    // Instead we may need to re-load the Publication from same URL, to get a separate reference.
    var newPub = publication
    newPub.manifest = audioPubManifest
    
    debugPrint("New audio readingOrder found: \(audioReadingOrder)")
    // Save the media-overlays for later position matching.
    self.mediaOverlays = mediaOverlays
    // Assign the publication, it should now conform to AudioBook.
    self._publication = newPub
    
    await super.initNavigator()
  }
  
  override public func play(fromLocator: Locator?) async {
    // Map the initial Text-based locator to Audio-based MediaOverlay Locator.
    let audioFromLocator = mapTextLocatorToMediaOverlayLocator(fromLocator)
    await super.play(fromLocator: audioFromLocator)
  }
  
  override public func seek(toLocator: Locator) async -> Bool {
    guard let navigator = _audioNavigator,
          let audioLocator = mapTextLocatorToMediaOverlayLocator(toLocator) else {
      return false
    }
    // Found a matching Audio Locator from given Text-based Locator.
    let navigated = await navigator.go(to: audioLocator)
    // Go will sometimes result in a pause, if buffering was necessary.
    // So we actively ensure we resume playing.
    navigator.play()
    return navigated
  }
  
  internal override func submitAudioLocatorToListener(_ location: Locator) {
    // Map audio offset Locator to a Text-based Locator, before submitting to listener.
    if let timeOffsetStr = location.locations.fragments.first(where: { $0.starts(with: "t=") })?.dropFirst(2),
       let timeOffset = Double(timeOffsetStr),
       let mediaOverlay = mediaOverlays.first(where: { $0.itemInRangeOfTime(timeOffset, inHref:  location.href.string) }),
       var textLocator = mediaOverlay.textLocator {
      if (!mediaOverlay.isEqual(lastMediaOverlayItem)) {
        // Matched a new MediaOverlayItem -> sync reader with its textLocator.
        lastMediaOverlayItem = mediaOverlay
        textLocator.locations.progression = location.locations.progression
        textLocator.locations.position = location.locations.position
        
        // TextLocator matching the audio position is created and should be sent back.
        self.listener?.timebasedNavigator(self, reachedLocator: textLocator, readingOrderLink: nil)
        self.listener?.timebasedNavigator(self, requestsHighlightAt: textLocator, withWordLocator: nil)
      }
    } else {
      debugPrint(TAG, "Did not find MediaOverlay matching audio Locator: \(location)")
    }
  }
  
  internal func mapTextLocatorToMediaOverlayLocator(_ textLocator: Locator?) -> Locator? {
    guard let textLocator = textLocator,
          let matchingItem = self.mediaOverlays.firstMap({ $0.itemFromLocator(textLocator)}),
          let audioLocator = matchingItem.audioLocator else {
      return nil
    }
    return audioLocator
  }
}
