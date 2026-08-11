import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Chapter collection object.
///
/// https://readium.org/webpub-manifest/schema/chapter.schema.json
@immutable
class Chapter extends BaseCollection {
  factory Chapter.fromJsonNumber(num number) => Chapter(position: number.toDouble());

  factory Chapter.fromJson(dynamic json) {
    if (json is String) {
      final position = double.tryParse(json);
      if (position != null) {
        return Chapter.fromJsonNumber(position);
      }
    }

    if (json is num) {
      return Chapter.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Chapter.fromJsonMap(json);
    } else {
      throw ArgumentError('Invalid JSON for Chapter: $json');
    }
  }

  factory Chapter.fromJsonMap(Map<String, dynamic> json) {
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
    final series = Series.listFromJson(jsonObject.opt('series', remove: true));

    return Chapter(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      series: series,
      additionalProperties: jsonObject,
    );
  }

  const Chapter({
    required super.position,
    super.localizedName,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.series = const [],
    super.additionalProperties,
  });

  static const _unset = Object();

  final List<Series> series;

  Chapter copyWith({
    Object? position = _unset,
    Object? localizedName = _unset,
    Object? identifier = _unset,
    Object? altIdentifiers = _unset,
    Object? localizedSortAs = _unset,
    Object? links = _unset,
    Object? series = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Chapter(
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
      series: identical(series, _unset) ? this.series : (series as List<Series>?)!,
      additionalProperties: mergeProperties,
    );
  }

  static List<Chapter> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Chapter.fromJson(e)).toList();
    } else {
      return [Chapter.fromJson(json)];
    }
  }

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (series.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..put('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putIterableIfNotEmpty('series', series);
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
    series,
    additionalProperties,
  ];
}
