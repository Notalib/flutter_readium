import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Chapter collection object.
///
/// https://readium.org/webpub-manifest/schema/chapter.schema.json
@immutable
class Chapter extends BaseCollection {
  factory Chapter.fromJsonNumber(num number) => Chapter(position: number.toDouble());

  factory Chapter.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      final position = double.tryParse(json);
      if (position != null) {
        return Chapter.fromJsonNumber(position);
      }
    }

    if (json is num) {
      return Chapter.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Chapter.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Chapter: $json');
    }
  }

  factory Chapter.fromJsonMap(
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

  final List<Series> series;

  Chapter copyWith({
    double? position,
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Series>? series,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Chapter(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      series: series ?? this.series,
      additionalProperties: mergeProperties,
    );
  }

  static List<Chapter> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Chapter.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else {
      return [Chapter.fromJson(json, normalizeHref: normalizeHref)];
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
