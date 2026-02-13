import 'package:meta/meta.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Episode collection object.
///
/// https://readium.org/webpub-manifest/schema/episode.schema.json
@immutable
class Episode extends BaseCollection {
  factory Episode.fromJsonNumber(num number) => Episode(position: number.toDouble());

  factory Episode.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      final position = double.tryParse(json);
      if (position != null) {
        return Episode.fromJsonNumber(position);
      }
    }

    if (json is num) {
      return Episode.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Episode.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Episode: $json');
    }
  }

  factory Episode.fromJsonMap(
    Map<String, dynamic> json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.from(json);

    final position = jsonObject.optNullableDouble('position', remove: true) ?? 0;
    final localizedName = LocalizedString.fromJsonDynamic(jsonObject.opt('name', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifiers = AltIdentifier.listFromJson(jsonObject.opt('altIdentifier', remove: true));
    final localizedSortAs = LocalizedString.fromJsonDynamic(
      jsonObject.opt('sortAs', remove: true) ?? jsonObject.opt('sort-as', remove: true),
    );
    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true), normalizeHref: normalizeHref);

    return Episode(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  const Episode({
    required super.position,
    super.localizedName,
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
        ..put('position', position)
        ..putOpt('identifier', identifier)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links);
    }
  }

  Episode copyWith({
    double? position,
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Episode(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }

  static List<Episode> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Episode.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Episode.fromJson(json, normalizeHref: normalizeHref)];
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
