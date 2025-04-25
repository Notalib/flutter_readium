import '../../index.dart';

part 'profile_holds.freezed.dart';
part 'profile_holds.g.dart';

/// PartOf: [Profile Json Schema](https://drafts.opds.io/schema/profile.schema.json)

@freezedExcludeUnion
abstract class ProfileHolds with _$ProfileHolds {
  @Assert('available == null || available >= 0')
  @Assert('total == null || total >= 0')
  @r2JsonSerializable
  const factory ProfileHolds({
    /// Number of holds allowed at any time for the users
    /// "minimum": 0
    final int? available,

    /// Number of holds currently available to the user"
    /// "minimum": 0
    final int? total,
  }) = _ProfileHolds;

  factory ProfileHolds.fromJson(final Map<String, dynamic> json) => _$ProfileHoldsFromJson(json);
}
