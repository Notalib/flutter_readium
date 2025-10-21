//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared
import ReadiumStreamer
import Flutter

class FlutterReadiumError {
  let message: String
  let code: String?
  let data: Any?
  let stack: [String: Any]?
  
  init(
    message: String,
    code: String? = nil,
    data: Any? = nil,
    details: [String: Any]? = nil
  ) {
    self.message = message
    self.code = code
    self.data = data
    self.stack = details
  }
  
  func toJson() -> [String: Any?] {
    let map: [String: Any?] = [
      "message": message,
      "code": code,
      "data": data,
      "stack": stack
    ]
    
    return map
  }
}

enum ReadiumError: Error {
  case formatNotSupported(String)
  case readingError(Error)
  case notFound(String?)
  case forbidden(String?)
  case publicationIsRestricted(Error)
  case readerViewNotFound
  case voiceNotFound
  case unknown(Error?)
}

extension Error {
  func toReadiumError() -> ReadiumError {
    switch self {
    case is AssetRetrieveError:
      return (self as! AssetRetrieveError).toReadiumError()
    case is AssetRetrieveURLError:
      return (self as! AssetRetrieveURLError).toReadiumError()
    case is PublicationOpenError:
      return (self as! PublicationOpenError).toReadiumError()
    default:
      return .unknown(self)
    }
  }
}

extension AssetRetrieveURLError {
  func toReadiumError() -> ReadiumError {
    switch self {
    case .formatNotSupported:
      return .formatNotSupported(self.localizedDescription)
    case .schemeNotSupported(let scheme):
      return .formatNotSupported("scheme not supported: \(scheme)")
    case .reading(let error):
      return .readingError(error)
    }
  }
}

extension AssetRetrieveError {
  func toReadiumError() -> ReadiumError {
    switch self {
    case .formatNotSupported:
      return .formatNotSupported(self.localizedDescription)
    case .reading(let error):
      return .readingError(error)
    }
  }
}

extension PublicationOpenError {
  func toReadiumError() -> ReadiumError {
    switch self {
    case .formatNotSupported:
      return .formatNotSupported(self.localizedDescription)
    case .reading(let error):
      return .readingError(error)
    }
  }
}

extension ReadiumError: UserErrorConvertible {
  func toFlutterError() -> FlutterError {
    switch self {
    case .formatNotSupported(let msg):
      return FlutterError(code: "formatNotSupported", message: self.localizedDescription, details: msg)
    case .readingError(let err):
      return FlutterError(code: "readingError", message: self.localizedDescription, details: err.localizedDescription)
    case .notFound(let msg):
      return FlutterError(code: "notFound", message: self.localizedDescription, details: msg)
    case .publicationIsRestricted(let err):
      return FlutterError(code: "forbidden", message: self.localizedDescription, details: err.localizedDescription)
    case .readerViewNotFound:
      return FlutterError(code: "readerViewNotFound", message: self.localizedDescription, details: nil)
    case .voiceNotFound:
      return FlutterError(code: "voiceNotFound", message: self.localizedDescription, details: nil)
    default:
      return FlutterError(code: "unknown", message: self.localizedDescription, details: nil)
    }
  }
  func userError() -> UserError {
    UserError(cause: self) {
      switch self {
      case .formatNotSupported:
        return "library_error_formatNotSupported".localized
      case .notFound:
        return "library_error_bookNotFound".localized
      case .readingError:
        return "library_error_readingError".localized
      case .forbidden(_):
        return "library_error_forbidden".localized
      case .readerViewNotFound:
        return "library_error_readerViewNotFound".localized
      case .voiceNotFound:
        return "library_error_voiceNotFound".localized
      case let .publicationIsRestricted(error):
        if let error = error as? UserErrorConvertible {
          return error.userError().message
        } else {
          return "library_error_publicationIsRestricted".localized
        }
      case .unknown:
        return "library_error_unknown".localized
      }
    }
  }
}
