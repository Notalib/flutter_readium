import '../index.dart';

part 'feed.freezed.dart';
part 'feed.g.dart';

/// OPDS Feed.
///
/// [Json Schema](https://drafts.opds.io/schema/feed.schema.json)
///
/// TODO:
/// "additionalProperties": {
///   "$ref": "https://readium.org/webpub-manifest/schema/subcollection.schema.json"
/// }
///
/// "anyOf": [
///   {
///     "required": [
///       "publications"
///     ]
///   },
///   {
///     "required": [
///       "navigation"
///     ]
///   },
///   {
///     "required": [
///       "groups"
///     ]
///   }
/// ]

@freezedExcludeUnion
abstract class Feed with _$Feed {
  @Assert(
    'publications != null || navigation != null || groups != null || xLocators != null || announcements != null',
    'Neither `publications`, `navigation`, `groups`, `xLocators` or `announcements` is Set',
  )
  @r2JsonSerializable
  const factory Feed({
    /// Contains feed-level metadata such as title or number of items.
    required final OPDSMetadata metadata,

    /// Feed-level links such as search or pagination.
    ///
    /// Note: Each Link Object in a links collection must contain a `rel` and
    /// the value must be:
    ///   "const": "self"
    ///
    /// "uniqueItems": true,
    /// TODO: This should be required.
    ///       Optional until Merkur sets the links property on announcement feed.
    final List<Link>? links,

    /// Facets are meant to re-order or obtain a subset for the current list of
    /// publications.
    ///
    /// "uniqueItems": true
    final List<Facet>? facets,

    /// Groups provide a curated experience, grouping publications or navigation
    /// links together.
    final List<Group>? groups,

    /// Navigation for the catalog using links.
    ///
    /// Note: Each Link Object in a navigation collection must contain a
    /// `title`.
    ///
    /// "uniqueItems": true
    final List<Link>? navigation,

    /// A list of publications that can be acquired.
    ///
    /// OPDS Publication
    ///
    /// "uniqueItems": true
    final List<OPDSPublication>? publications,

    /// A list of notification announcements.
    ///
    /// "uniqueItems": true
    final List<Announcement>? announcements,

    /// TODO: Extract X data to separate model class
    @JsonKey(name: 'x-locators') final List<Locator>? xLocators,
  }) = _Feed;

  factory Feed.fromJson(final Map<String, dynamic> json) => _$FeedFromJson(json);
}
