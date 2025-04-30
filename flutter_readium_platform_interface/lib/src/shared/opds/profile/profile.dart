import '../../index.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// OPDS User Profile 1.0
///
/// [Json Schema](https://drafts.opds.io/schema/profile.schema.json)

@freezedExcludeUnion
abstract class Profile with _$Profile {
  @r2JsonSerializable
  const factory Profile({
    required final String name,
    @JsonKey(name: 'x-username') required final String xUsername,
    @JsonKey(name: 'x-phone') final String? xPhone,
    @JsonKey(name: 'x-uni-login') final String? xUniLogin,
    @JsonKey(name: 'x-age') final int? xAge,
    // Boolean to identify whether Nota member is affected by loan restrictions on protected books
    @JsonKey(name: 'x-nota-restricted-loans') final bool? xNotaRestrictedLoans,
    final String? email,
    final List<ProfileHolds>? holds,
    final List<ProfileLoans>? loans,
    final List<Link>? links,
  }) = _Profile;

  factory Profile.fromJson(final Map<String, dynamic> json) => _$ProfileFromJson(json);
}
