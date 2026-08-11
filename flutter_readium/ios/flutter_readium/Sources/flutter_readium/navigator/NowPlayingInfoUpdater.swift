//
//  NowPlayingInfoUpdater.swift
//  Pods
//
//  Created by Daniel Dam Freiling on 28/10/2025.
//
import Combine
import ReadiumShared
import MediaPlayer
import ReadiumNavigator

public class NowPlayingInfoUpdater {

  public var infoType: ControlPanelInfoType
  public var timebase: ControlPanelTimebase
  internal var publication: Publication
  internal var lastReportedChapterNo: Int?
  private var coverSub: Set<AnyCancellable> = []

  lazy var fallbackChapterTitle: LocalizedString = LocalizedString.localized([
    "en": "Chapter",
    "da": "Kapitel",
    "sv": "Kapitel",
    "no": "Kapittel",
    "is": "Kafli",
  ])

  lazy var generatedFallbackChapterTitle: String = {
    let code = publication.metadata.language?.code.bcp47
    return fallbackChapterTitle.string(forLanguageCode: code)
  }()

  @Published var cover: UIImage? = nil

  init(
    withPublication publication: Publication,
    infoType: ControlPanelInfoType = .standard,
    timebase: ControlPanelTimebase = .chapter
  ) {
    self.publication = publication
    self.infoType = infoType
    self.timebase = timebase

    Task {
      // TODO: Should we limit cover size here?
      cover = try? await publication.cover().get()
    }
  }

  public func setupNowPlayingInfo() {
    let nowPlaying = NowPlayingInfo.shared

    // Initial publication metadata.
    nowPlaying.media = NowPlayingInfo.Media(
      title: publication.metadata.title ?? "",
      artist: publication.metadata.authors.map(\.name).joined(separator: ", "),
      chapterCount: publication.readingOrder.count
    )

    // Update the artwork once cover is loaded.
    $cover
      .sink { cover in
        nowPlaying.media?.artwork = cover
      }
      .store(in: &coverSub)
  }

  public func updatePlaybackFromInfo(_ info: MediaPlaybackInfo, withSpeedSetting speed: Double?) {
    let speed = info.state == .playing ? speed ?? 1.0 : 0.0

    updateChapterNo(info.resourceIndex)
    let playback = makePlaybackState(from: info, speed: speed)
    NowPlayingInfo.shared.playback = NowPlayingInfo.Playback(
      duration: playback.duration,
      elapsedTime: playback.elapsedTime,
      rate: playback.rate,
    )
  }

  public func updatePlaybackPosition(duration: Double?, elapsedTime: Double?, speed: Double?) {
    NowPlayingInfo.shared.playback = NowPlayingInfo.Playback(
      duration: duration,
      elapsedTime: elapsedTime,
      rate: speed,
    )
  }

  public func clearNowPlaying() {
    NowPlayingInfo.shared.clear()
    coverSub.forEach { $0.cancel() }
  }

  private func makePlaybackState(from info: MediaPlaybackInfo, speed: Double) -> (duration: Double?, elapsedTime: Double?, rate: Double) {
    guard timebase == .wholeBook else {
      return (info.duration, info.time, speed)
    }

    guard let publicationDuration = computePublicationDuration(publication.readingOrder.map { $0.duration }) else {
      return (info.duration, info.time, speed)
    }

    var elapsedTime = info.time
    for index in 0..<max(0, min(info.resourceIndex, publication.readingOrder.count)) {
      guard let duration = publication.readingOrder[index].duration,
            duration.isFinite,
            duration > 0 else {
        return (info.duration, info.time, speed)
      }
      elapsedTime += duration
    }

    return (publicationDuration, elapsedTime, speed)
  }

  public func updateChapterNo(_ chapterNo: Int?) {
    // Bail early if chapterNo hasn't changed.
    if (lastReportedChapterNo == chapterNo) {
      return
    }

    lastReportedChapterNo = chapterNo
    NowPlayingInfo.shared.media?.chapterNumber = chapterNo

    if (infoType == .standard || infoType == .standardWCh || chapterNo == nil) {
      self.standardNowPlayingInfo(chapterNo: chapterNo)
    } else {
      self.nonStandardNowPlayingInfo(chapterNo: chapterNo!)
    }
  }

  private func standardNowPlayingInfo(chapterNo: Int?) {
    let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
    var title = publication.metadata.title ?? ""

    NowPlayingInfo.shared.media?.artist = authors

    if (infoType == .standardWCh && chapterNo != nil) {
      let currentChapter = (publication.readingOrder.indices.contains(chapterNo!) ? publication.readingOrder[chapterNo!].title : nil) ?? "\(generatedFallbackChapterTitle) \(chapterNo! + 1)"
      title += " - \(currentChapter)"

      NowPlayingInfo.shared.media?.title = title
    } else {
      NowPlayingInfo.shared.media?.title = title
    }
  }

  private func nonStandardNowPlayingInfo(chapterNo: Int) {
    var currentChapter = publication.readingOrder.indices.contains(chapterNo) ? publication.readingOrder[chapterNo].title : nil
    let title = publication.metadata.title ?? ""

    if (infoType == .chapterTitleAuthor || infoType == .chapterTitle) {

      if (currentChapter == nil) {
        currentChapter = "\(generatedFallbackChapterTitle) \(chapterNo + 1)"
      }

      NowPlayingInfo.shared.media?.title = currentChapter!

      if (infoType == .chapterTitle) {
        NowPlayingInfo.shared.media?.artist = title
      } else {
        let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
        let titleWithAuthors = "\(title) - \(authors)"
        NowPlayingInfo.shared.media?.artist = titleWithAuthors
      }

    } else {
      NowPlayingInfo.shared.media?.artist = currentChapter
      NowPlayingInfo.shared.media?.title = title
    }
  }

  // MARK: Control Center

  public func setupCommandCenterControls(
    preferredIntervals: [Double],
    skipTrackEnabled: Bool = false,
    seekToEnabled: Bool = false,
    timebasedNavigator: FlutterTimebasedNavigator? = nil)
  {
    let rcc = MPRemoteCommandCenter.shared()

    func on(_ command: MPRemoteCommand, _ block: @escaping (FlutterTimebasedNavigator, MPRemoteCommandEvent) -> Void) {
      command.addTarget { [weak self] event in
        guard let _ = self,
              let navigator = timebasedNavigator else {
          return .noActionableNowPlayingItem
        }
        block(navigator, event)
        return .success
      }
    }

    @MainActor
    func emit(_ action: ExternalPlaybackCommandAction, position: TimeInterval? = nil) {
      FlutterReadiumPlugin.instance?.emitExternalPlaybackCommand(
        ReadiumExternalPlaybackCommand(
          action: action,
          position: position
        )
      )
    }

    on(rcc.playCommand) { navigator, _ in
      Task { @MainActor in
        emit(.play)
        await navigator.resume()
      }
    }

    on(rcc.pauseCommand) { navigator, _ in
      Task { @MainActor in
        emit(.pause)
        await navigator.pause()
      }
    }

    on(rcc.togglePlayPauseCommand) { navigator, _ in
      Task { @MainActor in
        let action: ExternalPlaybackCommandAction =
          FlutterReadiumPlugin.instance?.lastTimebasedPlayerState?.state == .playing ? .pause : .play
        emit(action)
        await navigator.togglePlayPause()
      }
    }

    if (skipTrackEnabled) {
      on(rcc.previousTrackCommand) { navigator, _ in
        Task { @MainActor in
          // TODO: Should these actually skip a full track?
          emit(.seekBackward)
          await navigator.seekBackward()
        }
      }

      on(rcc.nextTrackCommand) { navigator, _ in
        Task { @MainActor in
          // TODO: Should these actually skip a full track?
          emit(.seekForward)
          await navigator.seekForward()
        }
      }
    }

    rcc.skipBackwardCommand.preferredIntervals = preferredIntervals as [NSNumber]
    rcc.skipForwardCommand.preferredIntervals = preferredIntervals as [NSNumber]

    if (!preferredIntervals.isEmpty) {
      on(rcc.skipBackwardCommand) { navigator, _ in
        Task { @MainActor in
          emit(.seekBackward)
          await navigator.seekBackward()
        }
      }

      on(rcc.skipForwardCommand) { navigator, _ in
        Task { @MainActor in
          emit(.seekForward)
          await navigator.seekForward()
        }
      }
    }

    if (seekToEnabled) {
      on(rcc.changePlaybackPositionCommand) { navigator, event in
        guard let event = event as? MPChangePlaybackPositionCommandEvent else {
          return
        }
        let position = event.positionTime
        Task { @MainActor in
          emit(.seekTo, position: position)
          if self.timebase == .wholeBook,
             let audioNavigator = navigator as? FlutterAudioNavigator {
            await audioNavigator.seek(toPublicationOffset: position)
          } else {
            await navigator.seek(toOffset: position)
          }
        }
      }
    }
  }

  public func updateCommandCenterControls(timebasedNavigator: FlutterTimebasedNavigator? = nil) {
    let rcc = MPRemoteCommandCenter.shared()

    if let audioNavigator = timebasedNavigator as? FlutterAudioNavigator {
      Task { @MainActor in
        rcc.previousTrackCommand.isEnabled = audioNavigator.canGoBackward
        rcc.nextTrackCommand.isEnabled = audioNavigator.canGoForward
      }
    }
  }
}
