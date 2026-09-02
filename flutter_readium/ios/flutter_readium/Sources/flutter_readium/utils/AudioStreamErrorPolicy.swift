import Foundation
import ReadiumShared

/// `details.reason` values this module (and `FlutterReadiumPlugin`'s
/// `getResourceUrl`/`timebasedNavigator(encounteredError:)`) set alongside a
/// `ResourceReadError` or `AudioStreamError` code. Producer-specific hint, not
/// a strict cross-platform enum (see `docs/api-reference/error-codes.md#detailsreason`)
/// — kept as constants purely so call sites aren't raw string literals a typo
/// could slip past.
enum ReadiumErrorReason: String {
  /// No manifest entry matches the requested href.
  case notFound
  /// Failed to compute/open the on-disk resource cache file.
  case cache
  /// Ambient failure reported via the generic `timebasedNavigator(encounteredError:)` sink.
  case navigator
  /// Server rejected byte-range streaming for an audio resource.
  case rangeNotSupported
  /// Local filesystem error reading an audio resource.
  case fileSystem
}

/// What the audio navigator should do about a resource read error.
enum AudioStreamErrorAction: Equatable {
  /// Not a real failure (e.g. cancelled reads during seeks/dispose).
  case ignore
  /// Transient network-class error: attempt connection recovery.
  case retry
  /// Terminal error: emit failure state + error event with this code.
  /// `reason` carries a finer-grained classification into the error event's
  /// `data`, without adding a wire code.
  case fail(code: String, reason: ReadiumErrorReason? = nil)
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
        case .cancelled:
          return .ignore
        case .rangeNotSupported:
          return .fail(code: "AudioStreamError", reason: .rangeNotSupported)
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
        return .fail(code: "AudioStreamError", reason: .fileSystem)
      case .other:
        /// Unknown transport-level errors are usually network glue — worth a retry.
        return .retry
      }
    default:
      return .fail(code: "AudioStreamError")
    }
  }
}

/// Configures the automatic audio-stream error recovery loop: retry attempts,
/// exponential backoff, and stall detection. Mirrors Android's
/// `AudioRecoveryPolicy` / web's `AudioRecoveryPolicy`.
///
/// Consumer-configurable via `FlutterReadium().setAudioRecoveryPolicy(...)`
/// (see `flutter_readium_platform_interface`'s `AudioRecoveryPolicy`);
/// defaults reproduce the recovery behaviour that shipped before the policy
/// existed. Default: 1s, 2s, 4s backoff.
struct AudioRecoveryPolicy {
  var maxAttempts: Int = 3
  var backoffBaseSeconds: TimeInterval = 1.0
  /// How long, in seconds, playback can remain in the loading state before the
  /// stall watchdog synthesizes a retryable error and enters the recovery loop.
  var stallTimeoutSeconds: TimeInterval = 20.0
  /// How long, in seconds, a single recovery attempt has to prove playback
  /// advanced after rebuilding the player, before that attempt is abandoned and
  /// the loop moves on to the next one. Mirrors Android's/web's usage of the
  /// same field name.
  var connectionTimeoutSeconds: TimeInterval = 10.0

  func delay(forAttempt attempt: Int) -> TimeInterval {
    backoffBaseSeconds * pow(2.0, Double(max(attempt, 1) - 1))
  }

  /// Currently configured policy, set via `setAudioRecoveryPolicy`. Read by
  /// `FlutterAudioNavigator` at construction time - applies to the
  /// next-opened publication and to any in-flight recovery loop, not to an
  /// already-running attempt sequence.
  static var current: AudioRecoveryPolicy = AudioRecoveryPolicy()

  /// Parses a flat `[String: Any]` map (as sent over the method channel) into
  /// a policy, falling back to defaults for missing/invalid entries.
  static func fromMap(_ map: [String: Any]?) -> AudioRecoveryPolicy {
    guard let map else { return AudioRecoveryPolicy() }
    return AudioRecoveryPolicy(
      maxAttempts: (map["maxAttempts"] as? NSNumber)?.intValue ?? 3,
      backoffBaseSeconds: (map["backoffBaseSeconds"] as? NSNumber)?.doubleValue ?? 1.0,
      stallTimeoutSeconds: (map["stallTimeoutSeconds"] as? NSNumber)?.doubleValue ?? 20.0,
      connectionTimeoutSeconds: (map["connectionTimeoutSeconds"] as? NSNumber)?.doubleValue ?? 10.0
    )
  }
}
