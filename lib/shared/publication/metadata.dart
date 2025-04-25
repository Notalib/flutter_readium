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

    // TODO: Extract X data to separate model class
    @JsonKey(name: 'x-book-list-added') @dateTimeLocal final DateTime? xBooklistAdded,
    @JsonKey(name: 'x-bookshelf-added') @dateTimeLocal final DateTime? xBookshelfAdded,
    @JsonKey(name: 'x-bookshelf-last-access') final DateTime? xBookshelfLastAccess,
    @JsonKey(name: 'x-download-size-in-bytes') @Default(0) final int downloadSize,
    @JsonKey(name: 'x-e-book-visually-impaired')
    @Default(false)
    final bool xIsEbookForVisuallyImpaired,
    @JsonKey(name: 'x-edition') final String? xEdition,
    @JsonKey(name: 'x-has-text') @Default(false) final bool xHasText,
    @JsonKey(name: 'x-icon-url') final String? xIconUrl,
    @JsonKey(name: 'x-in-production') @Default(false) final bool xInProduction,
    @JsonKey(name: 'x-is-audio-book') @Default(false) final bool xIsAudiobook,
    @JsonKey(name: 'x-is-bookshelf-removable') @Default(true) final bool xIsBookshelfRemovable,
    @JsonKey(name: 'x-is-ebook') @Default(false) final bool xIsEbook,
    @JsonKey(name: 'x-is-epub') @Default(false) final bool xIsEPUB,
    @JsonKey(name: 'x-is-pdf') @Default(false) final bool xIsPDF,
    @JsonKey(name: 'x-is-read') @Default(false) final bool xIsRead,
    @JsonKey(name: 'x-isbn') final String? xISBN,
    @JsonKey(name: 'x-isbn10') final String? xISBN10,
    @JsonKey(name: 'x-isbn13') final String? xISBN13,
    @JsonKey(name: 'x-lix') final int? xLix,
    @JsonKey(name: 'x-library-id') final String? xLibraryId,
    @JsonKey(name: 'x-limited-loan-expiry-date') final DateTime? xLimitedLoanExpiryDate,
    @JsonKey(name: 'x-max-age') final int? xMaxAge,
    @JsonKey(name: 'x-min-age') final int? xMinAge,
    @JsonKey(name: 'x-must-be-protected') @Default(false) final bool xMustBeProtected,
    @JsonKey(name: 'x-next-available-loan-date') final DateTime? xNextAvailableLoanDate,
    @JsonKey(name: 'x-periodical-code') final String? xPeriodicalCode,
    @JsonKey(name: 'x-periodical-type') final String? xPeriodicalType,
    @JsonKey(name: 'x-preview') final int? xPreview,
    @JsonKey(name: 'x-previously-borrowed') @Default(false) final bool xHasPreviouslyBorrowed,
    @JsonKey(name: 'x-pub-year') final int? xPubYear,
    @JsonKey(name: 'x-published') @dateTimeLocal final DateTime? xPublished,
    @JsonKey(name: 'x-recorded-year') final int? xRecordedYear,
    @JsonKey(name: 'x-rights') final XRights? xRights,
    @JsonKey(name: 'x-sample-url') final String? xSampleUrl,
    @JsonKey(name: 'x-slow-reading') final bool? xSlowReading,
    @JsonKey(name: 'x-special-production') final String? xSpecialProduction,
    @JsonKey(name: 'x-target-audience') final String? xTargetAudience,
    @JsonKey(name: 'x-total-progression') final double? xTotalProgression,
    @JsonKey(name: 'x-under-production') @Default(false) final bool xUnderProduction,
    @JsonKey(name: 'x-note') final String? xNote,
  }) = _Metadata;

  factory Metadata.fromJson(final Map<String, dynamic> json) => _$MetadataFromJson(json);
}
