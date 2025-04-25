import '../../index.dart';

part 'encrypted.freezed.dart';
part 'encrypted.g.dart';

/// Indicates that a resource is encrypted/obfuscated and provides relevant
/// information for decryption.
///
/// PartOf: [Properties Json Schema](https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json)

@freezedExcludeUnion
abstract class Encrypted with _$Encrypted {
  @r2JsonSerializable
  const factory Encrypted({
    /// Identifies the algorithm used to encrypt the resource.
    ///
    /// "format": "uri"
    required final String algorithm,

    /// Compression method used on the resource.
    final String? compression,

    /// Original length of the resource in bytes before compression and/or
    /// encryption.
    final int? originalLength,

    /// Identifies the encryption profile used to encrypt the resource.
    ///
    /// "format": "uri"
    final String? profile,

    /// Identifies the encryption scheme used to encrypt the resource.
    ///
    /// "format": "uri"
    final String? scheme,
  }) = _Encrypted;

  factory Encrypted.fromJson(final Map<String, dynamic> json) => _$EncryptedFromJson(json);
}
