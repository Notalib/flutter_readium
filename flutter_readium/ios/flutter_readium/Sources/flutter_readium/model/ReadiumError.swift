//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared
import ReadiumStreamer
import Flutter

struct FlutterReadiumError {
  let message: String
  let code: String?
  let data: String?

  init(message: String, code: String? = nil, data: String? = nil) {
    self.message = message
    self.code = code
    self.data = data
  }

  func toJsonString() -> String {
    var map: [String: String] = ["message": message]
    if let code { map["code"] = code }
    if let data { map["data"] = data }
    guard
      let bytes = try? JSONSerialization.data(withJSONObject: map),
      let str = String(data: bytes, encoding: .utf8)
    else {
      return #"{"message":"FlutterReadiumError serialization failed"}"#
    }
    return str
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

extension HTTPError {
  var statusCode: HTTPStatus? {
    if case let .errorResponse(response) = self {
      return response.status
    }
    return nil
  }
  var responseHeaders: [String: String]? {
    if case let .errorResponse(response) = self {
      return response.headers
    }
    return nil
  }
  var responseBody: Data? {
    if case let .errorResponse(response) = self {
      return response.body
    }
    return nil
  }
}

extension AccessError {
  var httpError: HTTPError? {
    if case let .http(httpError) = self {
      return httpError
    }
    return nil
  }
  var fsError: FileSystemError? {
    if case let .fileSystem(fsErr) = self {
      return fsErr
    }
    return nil
  }
}

extension ReadError {
  var httpError: HTTPError? {
    if case let .access(.http(httpError)) = self {
      return httpError
    }
    return nil
  }
  var fsError: FileSystemError? {
    if case let .access(.fileSystem(fsErr)) = self {
      return fsErr
    }
    return nil
  }
}

extension ReadiumError: UserErrorConvertible {
  func toFlutterError() -> FlutterError {
    switch self {
    case .formatNotSupported(let msg):
      return FlutterError(code: "formatNotSupported", message: self.localizedDescription, details: msg)
    case .readingError(let err):
      switch err {
      case ReadiumShared.ArchiveOpenError.reading(.access(.http(let httpError))),
           ReadiumShared.ReadError.access(.http(let httpError)),
           ReadiumShared.AccessError.http(let httpError):
        return FlutterError(code: "readingError", message: "HTTPError(\(httpError.statusCode?.rawValue ?? 0)", details: httpError.responseHeaders)
      case ReadiumShared.ArchiveOpenError.reading(.access(.fileSystem(let fsError))),
           ReadiumShared.ReadError.access(.fileSystem(let fsError)),
           ReadiumShared.AccessError.fileSystem(let fsError):
        return FlutterError(code: "readingError", message: "FilesystemError", details: fsError.localizedDescription)
      default:
        return FlutterError(code: "readingError", message: self.localizedDescription, details: err.localizedDescription)
      }
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
