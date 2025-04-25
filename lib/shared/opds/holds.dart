import '../index.dart';

part 'holds.freezed.dart';
part 'holds.g.dart';

/// Library-specific features when a specific book is unavailable but provides
/// a hold list.
///
/// PartOf: [Properties Json Schema](https://drafts.opds.io/schema/properties.schema.json)

@freezedExcludeUnion
abstract class Holds with _$Holds {
  @Assert('position == null || position >= 0')
  @Assert('total == null || total >= 0')
  @r2JsonSerializable
  const factory Holds({
    /// "minimum": 0
    final int? position,

    /// "minimum": 0
    final int? total,
  }) = _Holds;

  factory Holds.fromJson(final Map<String, dynamic> json) => _$HoldsFromJson(json);
}
