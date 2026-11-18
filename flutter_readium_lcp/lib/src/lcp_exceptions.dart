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
  static const loanNotAvailable = 'lcpLoanNotAvailable';
  static const loanFailed = 'lcpLoanFailed';
  static const renewPeriod = 'lcpRenewPeriod';
  static const alreadyReturned = 'lcpAlreadyReturned';
  static const renewWebPage = 'lcpRenewWebPage';
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

/// A typed LCP failure from opening a publication or managing its loan. Get one from [fromReadiumException].
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
      case LcpErrorCodes.loanNotAvailable:
        return LcpLoanNotAvailableException._(message, exception);
      case LcpErrorCodes.loanFailed:
        return LcpLoanFailedException._(message, exception, isServerError: details?['reason'] == 'server');
      case LcpErrorCodes.renewPeriod:
        return LcpRenewPeriodException._(message, exception, maxRenewDate: _date(details?['maxRenewDate']));
      case LcpErrorCodes.alreadyReturned:
        return LcpAlreadyReturnedException._(message, exception);
      case LcpErrorCodes.renewWebPage:
        final url = details?['url'] as String?;
        if (url == null) return LcpUnexpectedException._(message, exception);
        return LcpRenewWebPageException._(message, exception, url);
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

/// The license has no renew link ([LcpLicenseInfo.canRenewLoan]) or no return link
/// ([LcpLicenseInfo.canReturnPublication]), so the action is not offered.
final class LcpLoanNotAvailableException extends LcpException {
  const LcpLoanNotAvailableException._(super.message, super.cause);
}

/// The license server refused or failed the renew or return request.
final class LcpLoanFailedException extends LcpException {
  const LcpLoanFailedException._(super.message, super.cause, {required this.isServerError});

  /// True when the server answered with an unexpected error or could not be reached. Both platforms
  /// report these together. False when the server rejected the request as invalid.
  final bool isServerError;
}

/// The server rejected the requested end date, so the loan was not renewed.
final class LcpRenewPeriodException extends LcpException {
  const LcpRenewPeriodException._(super.message, super.cause, {this.maxRenewDate});

  /// The latest end date the license allows, when the toolkit knows it.
  final DateTime? maxRenewDate;
}

/// The loan was already returned or has expired, so it cannot be returned.
final class LcpAlreadyReturnedException extends LcpException {
  const LcpAlreadyReturnedException._(super.message, super.cause);
}

/// The server renews loans through a web page, which the plugin cannot show. Open [url] in a
/// browser instead; the plugin does not renew the loan then.
final class LcpRenewWebPageException extends LcpException {
  const LcpRenewWebPageException._(super.message, super.cause, this.url);

  final String url;
}
