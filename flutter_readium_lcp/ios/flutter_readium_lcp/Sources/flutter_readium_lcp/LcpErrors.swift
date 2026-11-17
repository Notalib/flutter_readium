import Flutter
import Foundation
import ReadiumLCP
import ReadiumShared
import flutter_readium

/// Turns the toolkit's protection error into the wire codes `LcpErrorCodes` documents on the Dart side.
enum LcpErrors {
  /// The error as a `FlutterError`, for failures of the add-on's own method-channel calls.
  static func flutterError(_ error: Error?) -> FlutterError {
    let custom = map(error)
    return FlutterError(code: custom.code, message: custom.message, details: custom.data)
  }

  /// `error` is nil when the user cancelled the passphrase prompt: the toolkit hides that case.
  static func map(_ error: Error?) -> FlutterReadiumCustomError {
    guard let error else { return passphraseRequired("A passphrase is required to open this publication.") }
    guard let lcpError = error as? LCPError else { return unexpected(error) }

    switch lcpError {
    case .missingPassphrase:
      return passphraseRequired("A passphrase is required to open this publication.")
    case .licenseIntegrity(let clientError):
      switch clientError {
      case .certificateRevoked, .certificateSignatureInvalid, .licenseSignatureDateInvalid, .licenseSignatureInvalid:
        return licenseInvalid("signature", error)
      default:
        return licenseInvalid("integrity", error)
      }
    case .licenseProfileNotSupported:
      return licenseInvalid("profileNotSupported", error)
    case .parsing(.signature):
      return licenseInvalid("signature", error)
    case .parsing, .notALicenseDocument, .licenseContainer:
      return licenseInvalid("malformed", error)
    case .licenseStatus(let status):
      return licenseStatus(status)
    case .crlFetching:
      return FlutterReadiumCustomError(
        code: "lcpNetwork", message: "Could not fetch the certificate revocation list.", data: ["reason": "crl"])
    case .network:
      return FlutterReadiumCustomError(
        code: "lcpNetwork", message: "A network request for the license failed.", data: ["reason": "network"])
    default:
      return unexpected(error)
    }
  }

  private static func passphraseRequired(_ message: String) -> FlutterReadiumCustomError {
    FlutterReadiumCustomError(code: "lcpPassphraseRequired", message: message)
  }

  private static func licenseInvalid(_ reason: String, _ error: Error) -> FlutterReadiumCustomError {
    FlutterReadiumCustomError(
      code: "lcpLicenseInvalid", message: "The license is invalid: \(error)", data: ["reason": reason])
  }

  private static func unexpected(_ error: Error) -> FlutterReadiumCustomError {
    FlutterReadiumCustomError(code: "lcpError", message: "LCP failed: \(error)")
  }

  private static func licenseStatus(_ status: StatusError) -> FlutterReadiumCustomError {
    var data: [String: Any] = [:]
    let name: String
    switch status {
    case .cancelled(let date):
      name = "cancelled"
      data["date"] = iso(date)
    case .returned(let date):
      name = "returned"
      data["date"] = iso(date)
    case .expired(let start, let end):
      // The toolkit reports a license that has not started yet as expired. Android names it notStarted.
      if start > Date() {
        name = "notStarted"
        data["start"] = iso(start)
      } else {
        name = "expired"
        data["start"] = iso(start)
        data["end"] = iso(end)
      }
    case .revoked(let date, let devicesCount):
      name = "revoked"
      data["date"] = iso(date)
      data["devicesCount"] = devicesCount
    }
    data["status"] = name
    return FlutterReadiumCustomError(code: "lcpLicenseStatus", message: "The license is \(name).", data: data)
  }
}

func iso(_ date: Date) -> String {
  ISO8601DateFormatter().string(from: date)
}
