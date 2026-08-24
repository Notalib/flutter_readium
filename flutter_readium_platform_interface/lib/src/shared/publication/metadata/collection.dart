import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Collection
///
/// See: https://readium.org/webpub-manifest/schema/collection.schema.json
@immutable
class Collection extends BaseCollection {
  factory Collection.fromJsonString(String localizedString) => Collection(
    localizedName: LocalizedString.fromJsonString(localizedString),
  );

  factory Collection.fromJson(dynamic json) {
    if (json is String) {
      return Collection.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Collection.fromJsonMap(json);
    } else {
      ReadiumLog.e('Invalid JSON for Collection: $json');
      throw ArgumentError('Invalid JSON for Collection: $json');
    }
  }

  factory Collection.fromJsonMap(Map<String, dynamic> json) {
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

    return Collection(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  const Collection({
    required super.localizedName,
    super.position,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    super.additionalProperties,
  });

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..putOpt('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links);
    }
  }

  Collection copyWith({
    Object? position = unset,
    Object? localizedName = unset,
    Object? identifier = unset,
    Object? altIdentifiers = unset,
    Object? localizedSortAs = unset,
    Object? links = unset,
    Object? additionalProperties = unset,
  }) {
    final mergeProperties = copyAdditionalProperties(additionalProperties: additionalProperties);

    return Collection(
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
      additionalProperties: mergeProperties,
    );
  }

  static List<Collection> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Collection.fromJson(e)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Collection.fromJson(json)];
    }

    return [];
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
  ];
}
