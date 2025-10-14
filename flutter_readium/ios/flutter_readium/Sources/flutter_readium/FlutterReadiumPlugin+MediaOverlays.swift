import Combine
import Foundation
import MediaPlayer
import ReadiumNavigator
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

private let TAG = "ReadiumReaderPlugin/MediaOverlays"

extension FlutterReadiumPlugin {
  
  func openAsMediaOverlayAudiobook(_ publication: Publication) async -> Publication {
    print("Publication with Synchronized Narration reading-order found!")
    let narrationLinks = publication.readingOrder.compactMap {
      var link = $0.alternates.filterByMediaType(MediaType("application/vnd.syncnarr+json")!).first
      link?.title = $0.title
      return link
    }
    let narrationJson = await narrationLinks.asyncCompactMap { try? await publication.get($0)?.readAsJSONObject().get()
    }
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
    } as! [Link]
    
    // Copy the manifest and set its readingOrder to audioReadingOrder.
    var audioPubManifest = publication.manifest // var of struct == implicit copy
    audioPubManifest.readingOrder = audioReadingOrder
    audioPubManifest.metadata.conformsTo = [Publication.Profile.audiobook]
    
    var newPub = publication
    newPub.manifest = audioPubManifest
    
    print("New audio readingOrder found: \(audioReadingOrder)")
    // Save the media-overlays for later position matching.
    self.mediaOverlays = mediaOverlays
    // Assign the publication, it should now conform to AudioBook.
    return newPub
  }
}
