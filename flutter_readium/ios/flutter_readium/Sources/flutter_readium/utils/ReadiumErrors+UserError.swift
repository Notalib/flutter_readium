import Foundation
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer

extension ReadiumShared.ReadError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case let .access(error):
        return error.userError().message
      case .decoding:
        return "error_decoding".localized
      case .outOfMemory:
        return "error_oom".localized
      case .unsupportedOperation:
        return "error_read".localized
      case .cancelled:
        return "error_cancelled".localized
      }
    }
  }
}

extension ReadiumShared.AccessError: UserErrorConvertible {
  func userError() -> UserError {
    switch self {
    case let .http(error):
      return error.userError()
    case let .fileSystem(error):
      return error.userError()
    case .other:
      return UserError("error_read".localized, cause: self)
    }
  }
}

extension ReadiumShared.HTTPError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case let .errorResponse(response):
        switch response.status {
        case .notFound:
          return "error_not_found".localized
        case .unauthorized, .forbidden:
          return "error_forbidden".localized
        default:
          return "error_network".localized
        }
      case let .fileSystem(error):
        return error.userError().message
      case .cancelled:
        return "error_cancelled".localized
      case .malformedRequest, .malformedResponse, .timeout, .unreachable, .redirection, .security, .rangeNotSupported, .offline, .other:
        return "error_network".localized
      }
    }
  }
}

extension ReadiumShared.FileSystemError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .fileNotFound:
        return "error_not_found".localized
      case .forbidden:
        return "error_forbidden".localized
      case .io:
        return "error_io".localized
      case .outOfSpace:
        return "error_io".localized
      }
    }
  }
}

extension ReadiumShared.AssetRetrieveError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .formatNotSupported:
        return "reader_error_formatNotSupported".localized
      case let .reading(error):
        return error.userError().message
      }
    }
  }
}

extension ReadiumShared.AssetRetrieveURLError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .schemeNotSupported:
        return "reader_error_schemeNotSupported".localized
      case .formatNotSupported:
        return "reader_error_formatNotSupported".localized
      case let .reading(error):
        return error.userError().message
      }
    }
  }
}

extension ReadiumShared.SearchError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .publicationNotSearchable, .badQuery:
        return "reader_error_search".localized
      case let .reading(error):
        return error.userError().message
      }
    }
  }
}

extension ReadiumStreamer.PublicationOpenError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .formatNotSupported:
        return "reader_error_formatNotSupported".localized
      case let .reading(error):
        return error.userError().message
      }
    }
  }
}

extension ReadiumNavigator.NavigatorError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .copyForbidden:
        return "reader_error_copyForbidden".localized
      }
    }
  }
}

extension ReadiumNavigator.TTSError: UserErrorConvertible {
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .languageNotSupported:
        return "reader_error_tts_language_not_supported".localized
      case .other:
        return "reader_error_tts".localized
      }
    }
  }
}
