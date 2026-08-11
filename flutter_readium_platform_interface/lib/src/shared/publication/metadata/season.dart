import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Season collection object.
///
/// https://readium.org/webpub-manifest/schema/season.schema.json
@immutable
class Season extends BaseCollection {
  factory Season.fromJsonNumber(num number) => Season(position: number.toDouble());

  factory Season.fromJson(dynamic json) {
    if (json is String) {
      final position = int.tryParse(json);
      if (position != null) {
        return Season.fromJsonNumber(position);
      }
    }

    if (json is int) {
      return Season.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Season.fromJsonMap(json);
    } else {
      throw ArgumentError('Invalid JSON for Season: $json');
    }
  }

  factory Season.fromJsonMap(Map<String, dynamic> json) {
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

    final episodes = Episode.listFromJson(
      jsonObject.opt('episode', remove: true),
    );

    return Season(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      episodes: episodes,
      additionalProperties: jsonObject,
    );
  }

  const Season({
    required super.position,
    super.localizedName,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.episodes = const [],
    super.additionalProperties,
  });

  static const _unset = Object();

  final List<Episode> episodes;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (episodes.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..put('position', position)
        ..putOpt('identifier', identifier)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putOpt('episode', episodes.toSingleOrMultiJson());
    }
  }

  Season copyWith({
    Object? position = _unset,
    Object? localizedName = _unset,
    Object? identifier = _unset,
    Object? altIdentifiers = _unset,
    Object? localizedSortAs = _unset,
    Object? links = _unset,
    Object? episodes = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Season(
      position: identical(position, _unset) ? this.position : (position as double?)!,
      localizedName: identical(localizedName, _unset) ? this.localizedName : (localizedName as LocalizedString?)!,
      identifier: identical(identifier, _unset) ? this.identifier : (identifier as String?)!,
      altIdentifiers: identical(altIdentifiers, _unset)
          ? this.altIdentifiers
          : (altIdentifiers as List<AltIdentifier>?)!,
      localizedSortAs: identical(localizedSortAs, _unset)
          ? this.localizedSortAs
          : (localizedSortAs as LocalizedString?)!,
      links: identical(links, _unset) ? this.links : (links as List<Link>?)!,
      episodes: identical(episodes, _unset) ? this.episodes : (episodes as List<Episode>?)!,
      additionalProperties: mergeProperties,
    );
  }

  static List<Season> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Season.fromJson(e)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Season.fromJson(json)];
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
    episodes,
    additionalProperties,
  ];
}
