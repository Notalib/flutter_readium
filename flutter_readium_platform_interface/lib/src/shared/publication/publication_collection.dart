import '../index.dart';

part 'publication_collection.freezed.dart';
part 'publication_collection.g.dart';

/// Core Collection Model
///
/// Can be used as extension point in the Readium Web Publication Manifest.
///
/// [Json Schema](https://readium.org/webpub-manifest/schema/subcollection.schema.json)

/// TODO: Based on schema, is it valid to be extended by `Link`?!
@freezedExcludeUnion
abstract class PublicationCollection with _$PublicationCollection {
  @r2JsonSerializable
  const factory PublicationCollection({
    required final List<Link> links,
    required final Map<String, dynamic> metadata,

    /// JSON key used to reference this collection in its parent.
    final String? role,

    /// SubCollections indexed by their role in this collection.
    final List<PublicationCollection>? subCollections,
  }) = _PublicationCollection;

  factory PublicationCollection.fromJson(final Map<String, dynamic> json) =>
      _$PublicationCollectionFromJson(json);
}
