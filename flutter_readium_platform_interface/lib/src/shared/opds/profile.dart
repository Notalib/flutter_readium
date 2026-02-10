import 'package:dfunc/dfunc.dart';
import 'package:meta/meta.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../publication/link.dart';

/// OPDS Profile Document
/// https://drafts.opds.io/schema/opds-profile.schema.json
///
/// All OPDS User Profile documents must be served using the application/opds-profile+json media type.
@immutable
class Profile extends AdditionalProperties implements JSONable {
  factory Profile.fromJson(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final name = jsonObject.optNullableString('name', remove: true);
    final email = jsonObject.optNullableString('email', remove: true);
    final links =
        jsonObject
            .optJsonArray('links', remove: true)
            ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
            .nonNulls
            .toList() ??
        [];

    final loans = jsonObject.optJsonObject('loans', remove: true)?.let((it) => ProfileLoans.fromJson(it));
    final holds = jsonObject.optJsonObject('holds', remove: true)?.let((it) => ProfileHolds.fromJson(it));

    return Profile(
      name: name,
      email: email,
      links: links,
      loans: loans,
      holds: holds,
      additionalProperties: jsonObject,
    );
  }

  const Profile({this.name, this.email, this.links, this.loans, this.holds, super.additionalProperties});

  /// Given name for the user
  final String? name;

  /// Email address associated to the user
  final String? email;

  final List<Link>? links;

  final ProfileLoans? loans;

  final ProfileHolds? holds;

  @override
  Map<String, dynamic> toJson() => {...additionalProperties}
    ..putOpt('name', name)
    ..putOpt('email', email)
    ..putIterableIfNotEmpty('links', links)
    ..putJSONableIfNotEmpty('loans', loans)
    ..putJSONableIfNotEmpty('holds', holds);
}

@immutable
class ProfileHolds implements JSONable {
  const ProfileHolds({this.total, this.available});
  factory ProfileHolds.fromJson(Map<String, dynamic> json) =>
      ProfileHolds(total: json['total'] as int?, available: json['available'] as int?);

  /// Number of holds allowed at any time for the users.
  final int? total;

  /// Number of holds currently available to the user.
  final int? available;

  @override
  Map<String, dynamic> toJson() => {if (total != null) 'total': total, if (available != null) 'available': available};
}

class ProfileLoans implements JSONable {
  const ProfileLoans({this.total, this.available});
  factory ProfileLoans.fromJson(Map<String, dynamic> json) =>
      ProfileLoans(total: json['total'] as int?, available: json['available'] as int?);

  /// Number of loans allowed at any time for the users.
  final int? total;

  /// Number of loans currently available to the user.
  final int? available;

  @override
  Map<String, dynamic> toJson() => {if (total != null) 'total': total, if (available != null) 'available ': available};
}
