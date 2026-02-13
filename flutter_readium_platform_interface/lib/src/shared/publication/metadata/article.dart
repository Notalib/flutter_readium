import 'package:meta/meta.dart';

import '../../../utils/jsonable.dart';
import '../link.dart';
import '../localized_string.dart';
import 'alt_identifier.dart';
import 'base_collection.dart';
import 'contributor.dart';

/// Article
///
/// https://readium.org/webpub-manifest/schema/article.schema.json
@immutable
class Article extends BaseCollection {
  factory Article.fromString(String name) => Article(localizedName: LocalizedString.fromJsonString(name));

  factory Article.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      return Article.fromString(json);
    } else if (json is Map<String, dynamic>) {
      return Article.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Article: $json');
    }
  }

  factory Article.fromJsonMap(
    Map<String, dynamic> json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.of(json);

    final localizedName = LocalizedString.fromJsonDynamic(jsonObject.opt('name', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifiers = AltIdentifier.listFromJson(jsonObject.opt('altIdentifier', remove: true));
    final localizedSortAs = LocalizedString.fromJsonDynamic(jsonObject.opt('sortAs', remove: true));
    final author = jsonObject
        .optJsonArray('author', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final translator = jsonObject
        .optJsonArray('translator', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final editor = jsonObject
        .optJsonArray('editor', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final artist = jsonObject
        .optJsonArray('artist', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final illustrator = jsonObject
        .optJsonArray('illustrator', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final contributor = jsonObject
        .optJsonArray('contributor', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>, normalizeHref: normalizeHref))
        .nonNulls
        .toList();
    final description = jsonObject.optNullableString('description', remove: true);
    final numberOfPages = jsonObject.optNullableInt('numberOfPages', remove: true);
    final position = jsonObject.optNullableDouble('position', remove: true);
    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true), normalizeHref: normalizeHref);

    jsonObject
        .optJsonArray('links', remove: true)
        ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();

    return Article(
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      authors: author,
      translators: translator,
      editors: editor,
      artists: artist,
      illustrators: illustrator,
      contributors: contributor,
      description: description,
      numberOfPages: numberOfPages,
      position: position,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  const Article({
    required super.localizedName,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    this.authors,
    this.translators,
    this.editors,
    this.artists,
    this.illustrators,
    this.contributors,
    this.description,
    this.numberOfPages,
    super.position,
    super.links,
    super.additionalProperties,
  });

  static List<Article> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Article.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Article.fromJson(json, normalizeHref: normalizeHref)];
    }

    return [];
  }

  final List<Contributor>? authors;
  final List<Contributor>? translators;
  final List<Contributor>? editors;
  final List<Contributor>? artists;
  final List<Contributor>? illustrators;
  final List<Contributor>? contributors;
  final String? description;
  final int? numberOfPages;

  @override
  List<Object?> get props => [
    localizedName,
    identifier,
    altIdentifiers,
    localizedSortAs,
    authors,
    translators,
    editors,
    artists,
    illustrators,
    contributors,
    description,
    numberOfPages,
    position,
    links,
    additionalProperties,
  ];

  @override
  toJson() => <String, dynamic>{...additionalProperties}
    ..putOpt('name', localizedName)
    ..putOpt('identifier', identifier?.toString())
    ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
    ..putOpt('sortAs', localizedSortAs)
    ..putOpt('author', authors.toSingleOrMultiJson())
    ..putOpt('translator', translators.toSingleOrMultiJson())
    ..putOpt('editor', editors.toSingleOrMultiJson())
    ..putOpt('artist', artists.toSingleOrMultiJson())
    ..putOpt('illustrator', illustrators.toSingleOrMultiJson())
    ..putOpt('contributor', contributors.toSingleOrMultiJson())
    ..putOpt('description', description)
    ..putOpt('numberOfPages', numberOfPages)
    ..putOpt('position', position)
    ..putIterableIfNotEmpty('links', links);

  Article copyWith({
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Contributor>? authors,
    List<Contributor>? translators,
    List<Contributor>? editors,
    List<Contributor>? artists,
    List<Contributor>? illustrators,
    List<Contributor>? contributors,
    String? description,
    int? numberOfPages,
    double? position,
    List<Link>? links,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Article(
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      authors: authors ?? this.authors,
      translators: translators ?? this.translators,
      editors: editors ?? this.editors,
      artists: artists ?? this.artists,
      illustrators: illustrators ?? this.illustrators,
      contributors: contributors ?? this.contributors,
      description: description ?? this.description,
      numberOfPages: numberOfPages ?? this.numberOfPages,
      position: position ?? this.position,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }
}
