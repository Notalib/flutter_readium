import '../index.dart';

part 'metadata.freezed.dart';
part 'metadata.g.dart';

/// Metadata
///
/// [Json Schema](https://readium.org/webpub-manifest/schema/metadata.schema.json)

@freezedExcludeUnion
abstract class Metadata with _$Metadata {
  @Assert('duration == null || duration > 0.0')
  @Assert('numberOfPages == null || numberOfPages >= 1')
  @r2JsonSerializable
  const factory Metadata({
    /// anyOf:
    ///   String
    ///   Map<String, String>
    ///
    /// "additionalProperties": false,
    /// "minProperties": 1
    @localizeStringMapJson required final Map<String, String> title,
    @stringListJson final List<String>? conformsTo,

    /// "format": "uri"
    @JsonKey(name: '@type') final String? type,
    @contributorJson final List<Contributor>? artist,
    @contributorJson final List<Contributor>? author,
    @contributorJson final List<Contributor>? colorist,
    @contributorJson final List<Contributor>? contributor,
    @contributorJson final List<Contributor>? illustrator,
    @contributorJson final List<Contributor>? imprint,
    @contributorJson final List<Contributor>? inker,
    @contributorJson final List<Contributor>? penciler,
    @contributorJson final List<Contributor>? publisher,
    @contributorJson final List<Contributor>? letterer,
    @contributorJson final List<Contributor>? narrator,
    @contributorJson final List<Contributor>? translator,
    @contributorJson final List<Contributor>? editor,

    /// "exclusiveMinimum": 0
    final double? duration,

    /// "exclusiveMinimum": 0
    final int? numberOfPages,
    @Default(ReadingProgression.auto) final ReadingProgression readingProgression,
    @localizeStringListJson final List<String>? language,
    @subjectJson final List<Subject>? subject,

    /// anyOf:
    ///   String
    ///   Map<String, String>
    ///
    /// "additionalProperties": false,
    /// "minProperties": 1
    @localizeStringMapJsonNullable final Map<String, String>? subtitle,
    final BelongsTo? belongsTo,
    final String? description,

    /// "format": "uri"
    final String? identifier,
    @dateTimeLocal final DateTime? modified,
    @dateTimeLocal final DateTime? published,
    final String? sortAs,
    final Presentation? presentation,
  }) = _Metadata;

  factory Metadata.fromJson(final Map<String, dynamic> json) => _$MetadataFromJson(json);
}
