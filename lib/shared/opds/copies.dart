import '../index.dart';

part 'copies.freezed.dart';
part 'copies.g.dart';

/// Library-specific feature that contains information about the copies that a
/// library has acquired.
///
/// PartOf: [OPDS Properties Json Schema](https://drafts.opds.io/schema/properties.schema.json)

@freezedExcludeUnion
abstract class Copies with _$Copies {
  @Assert('available == null || available >= 0')
  @Assert('total == null || total >= 0')
  @r2JsonSerializable
  const factory Copies({
    /// "minimum": 0
    final int? available,

    /// "minimum": 0
    final int? total,
  }) = _Copies;

  factory Copies.fromJson(final Map<String, dynamic> json) => _$CopiesFromJson(json);
}
