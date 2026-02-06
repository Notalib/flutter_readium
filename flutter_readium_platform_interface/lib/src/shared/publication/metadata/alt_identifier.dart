import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../utils/jsonable.dart';

/// Alternate Identifiers
///
/// https://readium.org/webpub-manifest/schema/altIdentifier.schema.json
@immutable
class AltIdentifier with EquatableMixin implements JSONable {
  /// Factory to parse from JSON.
  factory AltIdentifier.fromJson(dynamic json) {
    if (json is String) {
      return AltIdentifier(scheme: json);
    } else if (json is Map<String, dynamic>) {
      final jsonObject = Map<String, dynamic>.of(json);
      final scheme = jsonObject.optNullableString('scheme', remove: true);
      if (scheme == null) {
        throw ArgumentError('Invalid AltIdentifier JSON: missing scheme: $json');
      }

      final value = jsonObject.optNullableString('value', remove: true);

      return AltIdentifier(scheme: scheme, value: value);
    } else {
      throw ArgumentError('Invalid AltIdentifier JSON: $json');
    }
  }
  const AltIdentifier({required this.scheme, this.value});

  final String scheme;
  final String? value;

  @override
  List<Object?> get props => [scheme, value];

  @override
  toJson() {
    if (value == null) {
      return scheme;
    } else {
      return <String, dynamic>{}
        ..put('scheme', scheme)
        ..putOpt('value', value);
    }
  }
}
