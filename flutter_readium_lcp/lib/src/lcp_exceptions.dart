import 'package:flutter_readium/flutter_readium.dart';

/// Wire codes native code puts on [ReadiumException.code] when opening an LCP publication fails.
///
/// These are a stable contract between the Swift and Kotlin sides and [LcpException.fromReadiumException].
abstract final class LcpErrorCodes {
  static const passphraseRequired = 'lcpPassphraseRequired';
  static const licenseInvalid = 'lcpLicenseInvalid';
  static const licenseStatus = 'lcpLicenseStatus';
  static const network = 'lcpNetwork';
  static const unexpected = 'lcpError';
}

/// Why a license failed its integrity checks.
enum LcpLicenseInvalidReason {
  /// The license did not pass the LCP client's checks (for example a key check).
  integrity,

  /// The license or its certificate chain has a bad signature, or the certificate is revoked or expired.
  signature,

  /// The license uses an LCP profile the app's LCP client library does not support.
  profileNotSupported,

  /// The license document or its container is unreadable.
  malformed;

  static LcpLicenseInvalidReason fromWire(String? value) =>
      LcpLicenseInvalidReason.values.asNameMap()[value] ?? LcpLicenseInvalidReason.integrity;
}

/// The state of a license that the license status document reports as unusable.
enum LcpLicenseStatus {
  expired,
  revoked,
  returned,
  cancelled,
  notStarted;

  static LcpLicenseStatus? fromWire(String? value) => LcpLicenseStatus.values.asNameMap()[value];
}

/// A typed LCP failure from opening a publication. Get one from [fromReadiumException].
sealed class LcpException implements Exception {
  const LcpException(this.message, this.cause);

  final String message;

  /// The exception core threw, with the raw wire code and details.
  final ReadiumException cause;

  /// Returns the typed LCP failure behind [exception], or null when it is not an LCP failure.
  static LcpException? fromReadiumException(final ReadiumException exception) {
    final details = exception.details;
    final message = exception.message;
    switch (exception.code) {
      case LcpErrorCodes.passphraseRequired:
        return LcpPassphraseRequiredException._(message, exception);
      case LcpErrorCodes.licenseInvalid:
        return LcpLicenseInvalidException._(
          message,
          exception,
          LcpLicenseInvalidReason.fromWire(details?['reason'] as String?),
        );
      case LcpErrorCodes.licenseStatus:
        final status = LcpLicenseStatus.fromWire(details?['status'] as String?);
        if (status == null) return LcpUnexpectedException._(message, exception);
        return LcpLicenseStatusException._(
          message,
          exception,
          status,
          date: _date(details?['date']),
          start: _date(details?['start']),
          end: _date(details?['end']),
          devicesCount: details?['devicesCount'] as int?,
        );
      case LcpErrorCodes.network:
        return LcpNetworkException._(message, exception, isCrl: details?['reason'] == 'crl');
      case LcpErrorCodes.unexpected:
        return LcpUnexpectedException._(message, exception);
    }
    return null;
  }

  static DateTime? _date(final Object? value) => value is String ? DateTime.tryParse(value) : null;

  @override
  String toString() => '$runtimeType: $message';
}

/// The license needs a passphrase and none was given: the prompt was cancelled, or no provider is set.
final class LcpPassphraseRequiredException extends LcpException {
  const LcpPassphraseRequiredException._(super.message, super.cause);
}

/// The license failed an integrity, signature or profile check, or could not be read.
final class LcpLicenseInvalidException extends LcpException {
  const LcpLicenseInvalidException._(super.message, super.cause, this.reason);

  final LcpLicenseInvalidReason reason;
}

/// The license status document says the license can no longer be used.
final class LcpLicenseStatusException extends LcpException {
  const LcpLicenseStatusException._(
    super.message,
    super.cause,
    this.status, {
    this.date,
    this.start,
    this.end,
    this.devicesCount,
  });

  final LcpLicenseStatus status;

  /// When the license was revoked, returned or cancelled. Null for the other statuses.
  final DateTime? date;

  /// Start of the validity period. Sent for [LcpLicenseStatus.notStarted] on both platforms, and for
  /// [LcpLicenseStatus.expired] on iOS only.
  final DateTime? start;

  /// End of the validity period. Sent for [LcpLicenseStatus.expired] on both platforms.
  final DateTime? end;

  /// Number of devices that registered the license. Sent for [LcpLicenseStatus.revoked] on both platforms.
  final int? devicesCount;
}

/// A network request for the license failed, including the certificate revocation list (CRL) fetch.
final class LcpNetworkException extends LcpException {
  const LcpNetworkException._(super.message, super.cause, {required this.isCrl});

  /// True when the failing request was the certificate revocation list.
  final bool isCrl;
}

/// Any other LCP failure.
final class LcpUnexpectedException extends LcpException {
  const LcpUnexpectedException._(super.message, super.cause);
}
