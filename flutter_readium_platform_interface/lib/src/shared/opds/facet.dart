import '../index.dart';

part 'facet.freezed.dart';
part 'facet.g.dart';

/// Facets are meant to re-order or obtain a subset for the current list of
/// publications.
///
/// PartOf: [Feed Json Schema](https://drafts.opds.io/schema/feed.schema.json)

@freezedExcludeUnion
abstract class Facet with _$Facet {
  @r2JsonSerializable
  const factory Facet({
    /// "uniqueItems": true
    final List<Link>? links,
    final OPDSMetadata? metadata,
  }) = _Facet;

  factory Facet.fromJson(final Map<String, dynamic> json) => _$FacetFromJson(json);
}

enum FacetTypeEnum {
  checkbox,
  interval,
  radiobutton,
  switchbutton,
  editable,
  expandable,
}
