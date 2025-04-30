import '../../index.dart';

part 'authentication.freezed.dart';
part 'authentication.g.dart';

/// OPDS Authentication Document.
///
/// [Json Schema](https://drafts.opds.io/schema/authentication.schema.json)

@freezedExcludeUnion
abstract class Authentication with _$Authentication {
  @r2JsonSerializable
  const factory Authentication({
    /// Unique identifier for the Catalog provider and canonical location for
    /// the Authentication Document.
    required final String id,

    /// A list of supported Authentication Flows.
    required final List<AuthenticationProperty> authentication,

    /// Title of the Catalog being accessed.
    required final String title,

    /// A description of the service being displayed to the user.
    final String? description,

    /// "uniqueItems": true
    final List<Link>? links,

    /// Version requirements.
    /// Key refers to a Client-ID.
    final Map<String, AppVersionRequirements>? versionRequirements,
  }) = _Authentication;

  factory Authentication.fromJson(final Map<String, dynamic> json) =>
      _$AuthenticationFromJson(json);
}
