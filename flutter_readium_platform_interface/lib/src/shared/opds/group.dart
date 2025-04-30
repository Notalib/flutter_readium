import '../index.dart';

part 'group.freezed.dart';
part 'group.g.dart';

/// Groups provide a curated experience, grouping publications or navigation
/// links together.
///
/// PartOf: [Feed Json Schema](https://drafts.opds.io/schema/feed.schema.json)

@freezedExcludeUnion
abstract class Group with _$Group {
  @r2JsonSerializable
  const factory Group({
    required final OPDSMetadata metadata,

    /// "uniqueItems": true
    final List<Link>? links,

    /// "uniqueItems": true
    final List<Link>? navigation,

    /// OPDS Publication
    final List<OPDSPublication>? publications,
  }) = _Group;

  factory Group.fromJson(final Map<String, dynamic> json) => _$GroupFromJson(json);
}
