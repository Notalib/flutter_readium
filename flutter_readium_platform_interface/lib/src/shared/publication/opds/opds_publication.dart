import '../../index.dart';

part 'opds_publication.freezed.dart';
part 'opds_publication.g.dart';

/// OPDS Publication.
///
/// [Json Schema](https://drafts.opds.io/schema/publication.schema.json)

@freezedExcludeUnion
abstract class OPDSPublication with _$OPDSPublication {
  @r2JsonSerializable
  const factory OPDSPublication({
    /// Images are meant to be displayed to the user when browsing publications.
    ///
    /// Note: At least one image resource must use one of the following formats:
    /// image/jpeg, image/png or image/gif.
    ///
    /// "minItems": 1
    required final List<Link> images,

    /// Note: A publication must contain at least one acquisition link in links
    /// collection:
    ///   "preview"
    ///   "http://opds-spec.org/acquisition"
    ///   "http://opds-spec.org/acquisition/buy"
    ///   "http://opds-spec.org/acquisition/open-access"
    ///   "http://opds-spec.org/acquisition/borrow"
    ///   "http://opds-spec.org/acquisition/sample"
    ///   "http://opds-spec.org/acquisition/subscribe"
    required final List<Link> links,

    /// r2 Metadata
    required final Metadata metadata,
  }) = _OPDSPublication;

  factory OPDSPublication.fromJson(final Map<String, dynamic> json) =>
      _$OPDSPublicationFromJson(json);
}
