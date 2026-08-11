import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Contributor
///
/// See: https://readium.org/webpub-manifest/schema/contributor.schema.json
@immutable
class Contributor extends BaseCollection {
  factory Contributor.fromJsonString(String name) => Contributor(localizedName: LocalizedString.fromJsonString(name));

  factory Contributor.fromJson(dynamic json) {
    if (json is String) {
      return Contributor.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Contributor.fromJsonMap(json);
    } else {
      throw ArgumentError('Invalid JSON for Contributor: $json');
    }
  }

  factory Contributor.fromJsonMap(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.from(json);

    final position = jsonObject.optNullableDouble('position', remove: true) ?? 0;
    final localizedName = LocalizedString.fromJsonDynamic(
      jsonObject.opt('name', remove: true),
    );
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifiers = AltIdentifier.listFromJson(
      jsonObject.opt('altIdentifier', remove: true),
    );
    final localizedSortAs = LocalizedString.fromJsonDynamic(
      jsonObject.opt('sortAs', remove: true) ?? jsonObject.opt('sort-as', remove: true),
    );
    final links = Link.fromJsonArray(
      jsonObject.optJsonArray('links', remove: true),
    );
    final roles = jsonObject.optJsonArray('role', remove: true)?.map((e) => e.toString()).toList();

    return Contributor(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      roles: roles,
      additionalProperties: jsonObject,
    );
  }

  const Contributor({
    required super.localizedName,
    super.position,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.roles,
    super.additionalProperties,
  });

  /// All values for the role element should be based on https://www.loc.gov/marc/relators/relaterm.html
  final List<String>? roles;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        position == null &&
        roles == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty)) {
      return localizedName!.toJson();
    } else {
      return <String, dynamic>{...additionalProperties}
        ..putOpt('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putIterableIfNotEmpty('role', roles);
    }
  }

  Contributor copyWith({
    Object? position = unset,
    Object? localizedName = unset,
    Object? identifier = unset,
    Object? altIdentifiers = unset,
    Object? localizedSortAs = unset,
    Object? links = unset,
    Object? roles = unset,
    Object? additionalProperties = unset,
  }) {
    final mergeProperties = copyAdditionalProperties(additionalProperties: additionalProperties);

    return Contributor(
      position: identical(position, unset) ? this.position : (position as double?)!,
      localizedName: identical(localizedName, unset) ? this.localizedName : (localizedName as LocalizedString?)!,
      identifier: identical(identifier, unset) ? this.identifier : (identifier as String?)!,
      altIdentifiers: identical(altIdentifiers, unset)
          ? this.altIdentifiers
          : (altIdentifiers as List<AltIdentifier>?)!,
      localizedSortAs: identical(localizedSortAs, unset)
          ? this.localizedSortAs
          : (localizedSortAs as LocalizedString?)!,
      links: identical(links, unset) ? this.links : (links as List<Link>?)!,
      roles: identical(roles, unset) ? this.roles : (roles as List<String>?)!,
      additionalProperties: mergeProperties,
    );
  }

  static List<Contributor> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Contributor.fromJson(e)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Contributor.fromJson(json)];
    } else {
      return [];
    }
  }

  @override
  List<Object?> get props => [
    position,
    localizedName,
    identifier,
    altIdentifiers,
    localizedSortAs,
    links,
    additionalProperties,
    roles,
  ];
}
