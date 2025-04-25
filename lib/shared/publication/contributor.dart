import '../index.dart';

part 'contributor.freezed.dart';
part 'contributor.g.dart';

/// Contributor
///
/// [Contributor Json Schema](https://readium.org/webpub-manifest/schema/contributor.schema.json)
/// [ContributorObject Json Object](https://readium.org/webpub-manifest/schema/contributor-object.schema.json)

@freezedExcludeUnion
abstract class Contributor with _$Contributor {
  @r2JsonSerializable
  const factory Contributor({
    /// anyOf:
    ///   String
    ///   Map<String, String>
    ///
    /// "additionalProperties": false,
    /// "minProperties": 1
    @localizeStringMapJson required final Map<String, String> name,

    /// "format": "uri"
    final String? identifier,
    final List<Link>? links,
    final double? position,

    /// anyOf:
    ///   String
    ///   List<String>
    @stringListJson final List<String>? role,
    @localizeStringMapJsonNullable final Map<String, String>? sortAs,
    @JsonKey(name: 'x-of-total') final double? xOfTotal,
  }) = _Contributor;

  factory Contributor.fromJson(final Map<String, dynamic> json) => _$ContributorFromJson(json);
}
