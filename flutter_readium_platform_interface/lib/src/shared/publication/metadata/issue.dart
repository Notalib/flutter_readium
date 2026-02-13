import 'package:meta/meta.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Issue collection object.
///
/// https://readium.org/webpub-manifest/schema/issue.schema.json
@immutable
class Issue extends BaseCollection {
  factory Issue.fromJsonNumber(num number) => Issue(position: number.toDouble());

  factory Issue.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      final position = int.tryParse(json);
      if (position != null) {
        return Issue.fromJsonNumber(position);
      }
    }

    if (json is int) {
      return Issue.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Issue.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Issue: $json');
    }
  }

  factory Issue.fromJsonMap(
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
    final articles = Article.listFromJson(jsonObject.opt('article', remove: true), normalizeHref: normalizeHref);
    final chapters = Chapter.listFromJson(
      jsonObject.optJsonArray('chapter', remove: true),
      normalizeHref: normalizeHref,
    );

    return Issue(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      articles: articles,
      chapters: chapters,
      additionalProperties: jsonObject,
    );
  }

  const Issue({
    required super.position,
    super.localizedName,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.articles = const [],
    this.chapters = const [],
    super.additionalProperties,
  });

  final List<Article> articles;
  final List<Chapter> chapters;

  Issue copyWith({
    double? position,
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Article>? articles,
    List<Chapter>? chapters,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Issue(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      articles: articles ?? this.articles,
      chapters: chapters ?? this.chapters,
      additionalProperties: mergeProperties,
    );
  }

  static List<Issue> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Issue.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Issue.fromJson(json, normalizeHref: normalizeHref)];
    }
    return [];
  }

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (articles.isEmpty) &&
        (chapters.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..put('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putOpt('article', articles.toSingleOrMultiJson())
        ..putOpt('chapter', chapters.toSingleOrMultiJson());
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
    articles,
    chapters,
    additionalProperties,
  ];
}
