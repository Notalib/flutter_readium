import 'package:meta/meta.dart';

/// Why the toolkit asks for a passphrase.
enum LcpPassphraseReason {
  /// No stored passphrase matches the license.
  notFound,

  /// The passphrase given for this license just now was wrong. Ask again.
  invalid;

  static LcpPassphraseReason fromWire(String? value) =>
      value == 'invalid' ? LcpPassphraseReason.invalid : LcpPassphraseReason.notFound;
}

/// What the native LCP toolkit knows about the license being opened, for building a passphrase prompt.
@immutable
class LcpPassphraseRequest {
  const LcpPassphraseRequest({
    required this.reason,
    required this.hint,
    required this.provider,
    required this.licenseId,
    this.hintUrl,
  });

  factory LcpPassphraseRequest.fromMap(final Map<Object?, Object?> map) => LcpPassphraseRequest(
    reason: LcpPassphraseReason.fromWire(map['reason'] as String?),
    hint: map['hint'] as String? ?? '',
    hintUrl: map['hintUrl'] as String?,
    provider: map['provider'] as String? ?? '',
    licenseId: map['licenseId'] as String? ?? '',
  );

  final LcpPassphraseReason reason;

  /// Text the license provider wrote to help the user remember the passphrase.
  final String hint;

  /// Page where the provider explains more about the passphrase, if the license has one.
  final String? hintUrl;

  /// URI of the license provider.
  final String provider;

  /// Identifier of the license.
  final String licenseId;

  @override
  String toString() => 'LcpPassphraseRequest(reason: $reason, provider: $provider, licenseId: $licenseId)';
}
