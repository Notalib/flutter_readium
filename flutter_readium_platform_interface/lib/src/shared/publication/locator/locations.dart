import '../../index.dart';

part 'locations.freezed.dart';
part 'locations.g.dart';

/// Location(s) object for Readium.
///
/// [Json Schema](https://github.com/readium/architecture/tree/master/models/locators)
@freezedExcludeUnion
abstract class Locations with _$Locations {
  @Assert('progression == null || (progression >= 0 && progression <= 1)')
  @Assert('position == null || position >= 1')
  @Assert('totalProgression == null || (totalProgression >= 0 && totalProgression <= 1)')
  @r2JsonSerializable
  const factory Locations({
    /// Contains one or more fragment in the resource referenced by the Locator Object.
    final List<String>? fragments,

    /// Progression in the resource expressed as a percentage. Or Float between 0 and 1.
    ///
    /// This description is inconsistent, unless progression really can be at most 1%.
    final double? progression,

    /// TODO: find better solution that does not include this, to make slider interactions better
    /// For when using slider to go to place in ebook
    final double? customProgressionOverride,

    /// An index in the publication.
    ///
    /// Integer where the value is > 1 (assuming that was meant to be ≥, not >?)
    final int? position,

    /// Progression in the publication expressed as a percentage.
    final double? totalProgression,

    /// HTML extension: A CSS Selector
    final String? cssSelector,

    /// HTML extension: partialCfi is an expression conforming to the "right-hand" side of the EPUB
    /// CFI syntax, that is to say: without the EPUB-specific OPF spine item reference that precedes
    /// the first ! exclamation mark (which denotes the "step indirection" into a publication
    /// document). Note that the wrapping epubcfi(***) syntax is not used for the partialCfi string,
    /// i.e. the "fragment" part of the CFI grammar is ignored.
    final String? partialCfi,

    /// HTML extension: This construct enables a serializable representation of a DOM Range.
    ///
    /// Note that end field is optional. When only the start field is specified, the domRange object
    /// represents a "collapsed" range that has identical "start" and "end" boundary points.
    final DomRange? domRange,

    /// Duration of a fragment. Could be a frame duration in comic books or duration of text in
    /// audiobooks.
    @JsonKey(
      name: 'x-fragment-duration',
      includeToJson: false,
      includeFromJson: false,
    )
    final Duration? xFragmentDuration,

    /// Duration of current chapter.
    @JsonKey(
      name: 'x-chapter-duration',
      includeToJson: false,
      includeFromJson: false,
    )
    final Duration? xChapterDuration,

    /// Duration of current progress in current chapter.
    @JsonKey(
      name: 'x-progression-duration',
      includeToJson: false,
      includeFromJson: false,
    )
    final Duration? xProgressionDuration,

    /// Duration of progress in publication.
    @JsonKey(
      name: 'x-total-progression-duration',
      includeToJson: false,
      includeFromJson: false,
    )
    final Duration? xTotalProgressionDuration,
  }) = _Locations;

  factory Locations.fromJson(final JsonObject json) => _$LocationsFromJson(json);
}
