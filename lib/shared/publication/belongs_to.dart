import '../index.dart';

part 'belongs_to.freezed.dart';
part 'belongs_to.g.dart';

/// PartOf: [Metadata Json Schema](https://readium.org/webpub-manifest/schema/metadata.schema.json)

@freezedExcludeUnion
abstract class BelongsTo with _$BelongsTo {
  @r2JsonSerializable
  const factory BelongsTo({
    @contributorJson final List<Contributor>? collection,
    @contributorJson final List<Contributor>? series,
  }) = _BelongsTo;

  factory BelongsTo.fromJson(final Map<String, dynamic> json) => _$BelongsToFromJson(json);
}
