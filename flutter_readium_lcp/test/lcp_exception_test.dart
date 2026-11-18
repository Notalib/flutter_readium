import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_readium_lcp/flutter_readium_lcp.dart';
import 'package:flutter_test/flutter_test.dart';

ReadiumException _wire(final String code, [final Map<String, dynamic>? details]) =>
    ReadiumException.fromPlatformException(PlatformException(code: code, message: 'msg', details: details));

void main() {
  group('LcpException.fromReadiumException', () {
    test('passphrase required', () {
      final err = LcpException.fromReadiumException(_wire(LcpErrorCodes.passphraseRequired));
      expect(err, isA<LcpPassphraseRequiredException>());
      expect(err!.message, 'msg');
      expect(err.cause.code, LcpErrorCodes.passphraseRequired);
    });

    test('license invalid carries the reason', () {
      final err = LcpException.fromReadiumException(_wire(LcpErrorCodes.licenseInvalid, {'reason': 'signature'}));
      expect((err! as LcpLicenseInvalidException).reason, LcpLicenseInvalidReason.signature);
    });

    test('license invalid with an unknown reason falls back to integrity', () {
      final err = LcpException.fromReadiumException(_wire(LcpErrorCodes.licenseInvalid, {'reason': 'new'}));
      expect((err! as LcpLicenseInvalidException).reason, LcpLicenseInvalidReason.integrity);
    });

    test('expired status carries start and end', () {
      final err = LcpException.fromReadiumException(
        _wire(LcpErrorCodes.licenseStatus, {
          'status': 'expired',
          'start': '2026-01-01T00:00:00Z',
          'end': '2026-02-01T00:00:00Z',
        }),
      );
      final status = err! as LcpLicenseStatusException;
      expect(status.status, LcpLicenseStatus.expired);
      expect(status.start, DateTime.utc(2026));
      expect(status.end, DateTime.utc(2026, 2));
      expect(status.date, isNull);
    });

    test('revoked status carries date and device count', () {
      final err = LcpException.fromReadiumException(
        _wire(LcpErrorCodes.licenseStatus, {
          'status': 'revoked',
          'date': '2026-03-04T05:06:07Z',
          'devicesCount': 2,
        }),
      );
      final status = err! as LcpLicenseStatusException;
      expect(status.status, LcpLicenseStatus.revoked);
      expect(status.date, DateTime.utc(2026, 3, 4, 5, 6, 7));
      expect(status.devicesCount, 2);
    });

    test('license status without a known status is unexpected', () {
      final err = LcpException.fromReadiumException(_wire(LcpErrorCodes.licenseStatus, {'status': 'weird'}));
      expect(err, isA<LcpUnexpectedException>());
    });

    test('network distinguishes the CRL fetch', () {
      final crl = LcpException.fromReadiumException(_wire(LcpErrorCodes.network, {'reason': 'crl'}));
      final other = LcpException.fromReadiumException(_wire(LcpErrorCodes.network));
      expect((crl! as LcpNetworkException).isCrl, isTrue);
      expect((other! as LcpNetworkException).isCrl, isFalse);
    });

    test('generic LCP failure', () {
      expect(LcpException.fromReadiumException(_wire(LcpErrorCodes.unexpected)), isA<LcpUnexpectedException>());
    });

    test('non-LCP codes return null', () {
      expect(LcpException.fromReadiumException(_wire('forbidden')), isNull);
      expect(LcpException.fromReadiumException(_wire('readingError')), isNull);
    });
  });
}
