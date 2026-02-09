import 'package:meta/meta.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

@immutable
class Issue extends BaseCollection {
  factory Issue.fromJsonNumber(int number) => Issue(position: number);
  factory Issue.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
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

    final position = jsonObject.optNullableInt('position', remove: true) ?? 0;
    final localizedName = LocalizedString.fromJson(jsonObject.opt('name', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifier = AltIdentifier.fromJson(jsonObject.opt('altIdentifier', remove: true));
    final localizedSortAs = LocalizedString.fromJson(
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
      altIdentifier: altIdentifier,
      localizedSortAs: localizedSortAs,
      links: links,
      articles: articles,
      chapters: chapters,
      additionalProperties: jsonObject,
    );
  }

  const Issue({
    required this.position,
    super.localizedName,
    super.identifier,
    super.altIdentifier,
    super.localizedSortAs,
    super.links,
    this.articles = const [],
    this.chapters = const [],
    super.additionalProperties,
  });

  final int position;

  final List<Article> articles;
  final List<Chapter> chapters;

  Issue copyWith({
    int? position,
    LocalizedString? localizedName,
    String? identifier,
    AltIdentifier? altIdentifier,
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
      altIdentifier: altIdentifier ?? this.altIdentifier,
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
    } else {
      return [Issue.fromJson(json, normalizeHref: normalizeHref)];
    }
  }

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifier == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (articles.isEmpty) &&
        (chapters.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..put('position', position)
        ..putJSONableIfNotEmpty('altIdentifier', altIdentifier)
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putIterableIfNotEmpty('article', articles)
        ..putIterableIfNotEmpty('chapter', chapters);
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
    articles,
    chapters,
    additionalProperties,
  ];
}
