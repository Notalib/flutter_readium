import '../../index.dart';

part 'authentication_property.freezed.dart';
part 'authentication_property.g.dart';

/// Supported Authentication Flows.
///
/// PartOf: [Authentication Json Schema](https://drafts.opds.io/schema/authentication.schema.json)

@freezedExcludeUnion
abstract class AuthenticationProperty with _$AuthenticationProperty {
  @r2JsonSerializable
  const factory AuthenticationProperty({
    /// "format": "uri"
    required final String type,
    final Labels? labels,

    /// "uniqueItems": true
    final List<Link>? links,
  }) = _AuthenticationProperty;

  factory AuthenticationProperty.fromJson(final Map<String, dynamic> json) =>
      _$AuthenticationPropertyFromJson(json);
}
