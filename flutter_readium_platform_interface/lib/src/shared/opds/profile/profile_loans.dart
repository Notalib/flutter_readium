import '../../index.dart';

part 'profile_loans.freezed.dart';
part 'profile_loans.g.dart';

/// PartOf: [Profile Json Schema](https://drafts.opds.io/schema/profile.schema.json)

@freezedExcludeUnion
abstract class ProfileLoans with _$ProfileLoans {
  @Assert('available == null || available >= 0')
  @Assert('total == null || total >= 0')
  @r2JsonSerializable
  const factory ProfileLoans({
    /// Number of loans allowed at any time for the users
    /// "minimum": 0
    final int? available,

    /// Number of loans currently available to the user
    /// "minimum": 0
    final int? total,
  }) = _ProfileLoans;

  factory ProfileLoans.fromJson(final Map<String, dynamic> json) => _$ProfileLoansFromJson(json);
}
