import Foundation
import ReadiumShared

/// What the audio navigator should do about a resource read error.
enum AudioStreamErrorAction: Equatable {
  /// Not a real failure (e.g. cancelled reads during seeks/dispose).
  case ignore
  /// Transient network-class error: attempt connection recovery.
  case retry
  /// Terminal error: emit failure state + error event with this code.
  case fail(code: String)
}

extension ReadError {
  /// The HTTP status code behind this error, if it's an `.access(.http(.errorResponse))`
  /// failure. `nil` for all other read-error shapes (offline, timeout, filesystem, etc.).
  var httpStatus: Int? {
    if case let .access(.http(.errorResponse(response))) = self {
      return response.status.rawValue
    }
    return nil
  }

  /// Classifies a resource read error for audio streaming purposes.
  var audioStreamAction: AudioStreamErrorAction {
    switch self {
    case .cancelled:
      return .ignore
    case let .access(access):
      switch access {
      case let .http(httpError):
        switch httpError {
        case .timeout, .unreachable, .offline, .redirection, .malformedResponse:
          return .retry
        case let .errorResponse(response):
          switch response.status.rawValue {
          case 401, 403:
            return .fail(code: "AudioStreamAuthError")
          case 500...:
            return .retry
          default:
            return .fail(code: "AudioStreamHTTPError")
          }
        default:
          return .fail(code: "AudioStreamNetworkError")
        }
      case .fileSystem:
        return .fail(code: "AudioStreamFileError")
      case .other:
        /// Unknown transport-level errors are usually network glue — worth a retry.
        return .retry
      }
    default:
      return .fail(code: "AudioStreamError")
    }
  }
}

/// Exponential backoff policy for audio stream recovery: 1s, 2s, 4s.
struct AudioRecoveryPolicy {
  var maxAttempts: Int = 3

  func delay(forAttempt attempt: Int) -> TimeInterval {
    pow(2.0, Double(max(attempt, 1) - 1))
  }
}
