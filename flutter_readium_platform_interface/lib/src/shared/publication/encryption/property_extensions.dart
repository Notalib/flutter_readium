import 'package:equatable/equatable.dart';

import '../../../utils/jsonable.dart';
import '../properties.dart';

// See https://github.com/readium/webpub-manifest/blob/master/schema/extensions/encryption/properties.schema.json
extension EncryptionPropertiesExtension on Properties {
  static const String _encryptedKey = 'encrypted';
  EncryptedProperties? get encrypted => EncryptedProperties.fromJson(additionalProperties.optJsonObject(_encryptedKey));

  Properties setEncrypted(final EncryptedProperties? value) =>
      copyWith(additionalProperties: {_encryptedKey: value?.toJson()});
}

class EncryptedProperties with EquatableMixin implements JSONable {
  const EncryptedProperties({
    required this.algorithm,
    this.compression,
    this.originalLength,
    this.profile,
    this.scheme,
  });

  final String algorithm;
  final String? compression;
  final int? originalLength;
  final String? profile;
  final String? scheme;

  @override
  // TODO: implement props
  List<Object?> get props => [algorithm, compression, originalLength, profile, scheme];

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'algorithm': algorithm,
    if (compression != null) 'compression': compression,
    if (originalLength != null) 'originalLength': originalLength,
    if (profile != null) 'profile': profile,
    if (scheme != null) 'scheme': scheme,
  };

  static EncryptedProperties? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final algorithm = jsonObject.optNullableString('algorithm', remove: true);
    if (algorithm == null) {
      return null;
    }

    return EncryptedProperties(
      algorithm: algorithm,
      compression: jsonObject.optNullableString('compression', remove: true),
      originalLength: jsonObject.optNullableInt('originalLength', remove: true),
      profile: jsonObject.optNullableString('profile', remove: true),
      scheme: jsonObject.optNullableString('scheme', remove: true),
    );
  }
}
