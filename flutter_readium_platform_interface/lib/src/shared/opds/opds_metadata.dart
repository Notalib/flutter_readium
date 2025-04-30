import '../index.dart';

part 'opds_metadata.freezed.dart';
part 'opds_metadata.g.dart';

/// OPDS Feed Metadata
///
/// [Json Schema](https://drafts.opds.io/schema/feed-metadata.schema.json)

@freezedExcludeUnion
abstract class OPDSMetadata with _$OPDSMetadata {
  @Assert('currentPage == null || currentPage >= 1')
  @Assert('itemsPerPage == null || itemsPerPage >= 1')
  @Assert('numberOfItems == null || numberOfItems >= 0')
  @Assert('subtitle == null || subtitle.length >= 1')
  @r2JsonSerializable
  const factory OPDSMetadata({
    /// anyOf:
    ///   String
    ///   List<String>
    ///   Map<String, String>
    ///
    /// "additionalProperties": false,
    /// "minProperties": 1
    @localizeStringMapJson required final Map<String, String> title,

    /// "format": "uri"
    @JsonKey(name: '@type') final String? type,

    /// "exclusiveMinimum": 0
    final int? currentPage,
    final String? description,

    /// "format": "uri"
    final String? identifier,

    /// "exclusiveMinimum": 0
    final int? itemsPerPage,
    @dateTimeLocal final DateTime? modified,

    /// "minimum": 0
    final int? numberOfItems,

    /// anyOf:
    ///   String
    ///   List<String>
    ///   Map<String, String>
    ///
    /// "additionalProperties": false,
    /// "minProperties": 1
    @localizeStringMapJsonNullable final Map<String, String>? subtitle,

    /// TODO: extract x properties
    @JsonKey(name: 'x-body') final String? xBody,
    @JsonKey(name: 'x-created-by') final String? xCreatedBy,
    @JsonKey(name: 'x-created-date') @dateTimeLocal final DateTime? xCreatedDate,
    @JsonKey(name: 'x-facet-type') final FacetTypeEnum? xFacetType,
    @JsonKey(name: 'x-icon-url') final String? xIconUrl,
    @JsonKey(name: 'x-image-url') final String? xImageUrl,
    @JsonKey(name: 'x-series-title') final String? xSeriesTitle,
    @JsonKey(name: 'x-suggestion-type') final String? xSuggestionType,
    @JsonKey(name: 'x-summary') final String? xSummary,
    @JsonKey(name: 'x-teaser') final String? xTeaser,
  }) = _OPDSMetadata;

  factory OPDSMetadata.fromJson(final Map<String, dynamic> json) => _$OPDSMetadataFromJson(json);
}
