import 'package:meta/meta.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Issue collection object.
///
/// https://readium.org/webpub-manifest/schema/issue.schema.json
@immutable
class Issue extends BaseCollection {
  factory Issue.fromJsonNumber(num number) => Issue(position: number.toDouble());

  factory Issue.fromJson(dynamic json) {
    if (json is String) {
      final position = int.tryParse(json);
      if (position != null) {
        return Issue.fromJsonNumber(position);
      }
    }

    if (json is int) {
      return Issue.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Issue.fromJsonMap(json);
    } else {
      throw ArgumentError('Invalid JSON for Issue: $json');
    }
  }

  factory Issue.fromJsonMap(Map<String, dynamic> json) {
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
    final articles = Article.listFromJson(
      jsonObject.opt('article', remove: true),
    );
    final chapters = Chapter.listFromJson(
      jsonObject.optJsonArray('chapter', remove: true),
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

  static const _unset = Object();

  final List<Article> articles;
  final List<Chapter> chapters;

  Issue copyWith({
    Object? position = _unset,
    Object? localizedName = _unset,
    Object? identifier = _unset,
    Object? altIdentifiers = _unset,
    Object? localizedSortAs = _unset,
    Object? links = _unset,
    Object? articles = _unset,
    Object? chapters = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Issue(
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
      articles: identical(articles, _unset) ? this.articles : (articles as List<Article>?)!,
      chapters: identical(chapters, _unset) ? this.chapters : (chapters as List<Chapter>?)!,
      additionalProperties: mergeProperties,
    );
  }

  static List<Issue> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Issue.fromJson(e)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Issue.fromJson(json)];
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
