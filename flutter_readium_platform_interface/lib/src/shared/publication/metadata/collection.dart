import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Collection
/// See: https://readium.org/webpub-manifest/schema/collection.schema.json
@immutable
class Collection extends BaseCollection {
  factory Collection.fromJsonString(String localizedString) =>
      Collection(localizedName: LocalizedString.fromJsonString(localizedString));
  factory Collection.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      return Collection.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Collection.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Collection: $json');
    }
  }

  factory Collection.fromJsonMap(
    Map<String, dynamic> json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.from(json);

    final position = jsonObject.optNullableInt('position', remove: true) ?? 0;
    final localizedName = LocalizedString.fromJson(jsonObject.opt('name', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifier = AltIdentifier.fromJson(jsonObject.opt('altIdentifier', remove: true));
    final localizedSortAs = LocalizedString.fromJson(
      jsonObject.opt('sortAs', remove: true) ?? jsonObject.opt('sort-as', remove: true),
    );
    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true), normalizeHref: normalizeHref);

    return Collection(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifier: altIdentifier,
      localizedSortAs: localizedSortAs,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  const Collection({
    required super.localizedName,
    this.position,
    super.identifier,
    super.altIdentifier,
    super.localizedSortAs,
    super.links,
    super.additionalProperties,
  });

  final int? position;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifier == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..putOpt('position', position)
        ..putJSONableIfNotEmpty('altIdentifier', altIdentifier)
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links);
    }
  }

  Collection copyWith({
    int? position,
    LocalizedString? localizedName,
    String? identifier,
    AltIdentifier? altIdentifier,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Collection(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifier: altIdentifier ?? this.altIdentifier,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }

  static List<Collection> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is List) {
      return json.map((e) => Collection.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else {
      return [Collection.fromJson(json, normalizeHref: normalizeHref)];
    }
  }

  @override
  List<Object?> get props => [
    position,
    localizedName,
    identifier,
    altIdentifier,
    localizedSortAs,
    links,
    additionalProperties,
  ];
}
