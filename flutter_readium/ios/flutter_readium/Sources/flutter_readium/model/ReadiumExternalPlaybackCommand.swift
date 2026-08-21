import Foundation

enum ExternalPlaybackCommandAction: String {
  case play
  case pause
  case togglePlayPause
  case seekForward
  case seekBackward
  case seekTo
  case next
  case previous
  case unknown
}

struct ReadiumExternalPlaybackCommand {
  let action: ExternalPlaybackCommandAction
  let position: TimeInterval?

  init(
    action: ExternalPlaybackCommandAction,
    position: TimeInterval? = nil
  ) {
    self.action = action
    self.position = position
  }

  func toMap() -> [String: Any] {
    var map: [String: Any] = [
      "action": action.rawValue
    ]

    if let position = position {
      map["position"] = Int(position * 1000)
    }

    return map
  }
}
