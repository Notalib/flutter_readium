import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../utils/additional_properties.dart';
import '../../../utils/jsonable.dart';
import '../link.dart';
import '../localized_string.dart';
import 'alt_identifier.dart';
import 'contributor.dart';

/// Article Object for the Readium Web Publication Manifest.
/// https://readium.org/webpub-manifest/schema/article.schema.json
@immutable
class Article extends AdditionalProperties with EquatableMixin implements JSONable {
  factory Article.fromJsonMap(Map<String, dynamic> json) {
    final jsonObject = Map<String, dynamic>.of(json);

    final localizedName = LocalizedString.fromJsonDynamic(jsonObject.opt('name', remove: true));
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final altIdentifier = jsonObject
        .optJsonObject('altIdentifier', remove: true)
        ?.let((it) => AltIdentifier.fromJson(it));
    final sortAs = jsonObject.optJsonObject('sortAs', remove: true)?.cast<String, String>();
    final author = jsonObject
        .optJsonArray('author', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final translator = jsonObject
        .optJsonArray('translator', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final editor = jsonObject
        .optJsonArray('editor', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final artist = jsonObject
        .optJsonArray('artist', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final illustrator = jsonObject
        .optJsonArray('illustrator', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final contributor = jsonObject
        .optJsonArray('contributor', remove: true)
        ?.map((e) => Contributor.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();
    final description = jsonObject.optNullableString('description', remove: true);
    final numberOfPages = jsonObject.optNullableInt('numberOfPages', remove: true);
    final position = jsonObject.optNullableDouble('position', remove: true);
    final links = jsonObject
        .optJsonArray('links', remove: true)
        ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
        .nonNulls
        .toList();

    return Article(
      localizedName: localizedName,
      identifier: identifier,
      altIdentifier: altIdentifier,
      sortAs: sortAs,
      author: author,
      translator: translator,
      editor: editor,
      artist: artist,
      illustrator: illustrator,
      contributor: contributor,
      description: description,
      numberOfPages: numberOfPages,
      position: position,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  factory Article.fromString(String name) => Article(localizedName: LocalizedString.fromJsonString(name));

  const Article({
    required this.localizedName,
    this.identifier,
    this.altIdentifier,
    this.sortAs,
    this.author,
    this.translator,
    this.editor,
    this.artist,
    this.illustrator,
    this.contributor,
    this.description,
    this.numberOfPages,
    this.position,
    this.links,
    super.additionalProperties,
  });

  static List<Article> fromJson(dynamic json) {
    if (json is String) {
      return [Article.fromString(json)];
    } else if (json is List) {
      final list = <Article>[];
      for (final item in json) {
        if (item is String) {
          list.add(Article.fromString(item));
        } else if (item is Map<String, dynamic>) {
          list.add(Article.fromJsonMap(item));
        } else {
          throw ArgumentError('Invalid Article JSON: $json');
        }
      }

      return list;
    } else if (json is Map<String, dynamic>) {
      return [Article.fromJsonMap(json)];
    } else {
      throw ArgumentError('Invalid Article JSON: $json');
    }
  }

  final LocalizedString? localizedName;
  final String? identifier;
  final AltIdentifier? altIdentifier;
  final Map<String, String>? sortAs;
  final List<Contributor>? author;
  final List<Contributor>? translator;
  final List<Contributor>? editor;
  final List<Contributor>? artist;
  final List<Contributor>? illustrator;
  final List<Contributor>? contributor;
  final String? description;
  final int? numberOfPages;
  final double? position;
  final List<Link>? links;

  @override
  List<Object?> get props => [
    localizedName,
    identifier,
    altIdentifier,
    sortAs,
    author,
    translator,
    editor,
    artist,
    illustrator,
    contributor,
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
    ..putOpt('altIdentifier', altIdentifier)
    ..putOpt('sortAs', sortAs)
    ..putIterableIfNotEmpty('author', author)
    ..putIterableIfNotEmpty('translator', translator)
    ..putIterableIfNotEmpty('editor', editor)
    ..putIterableIfNotEmpty('artist', artist)
    ..putIterableIfNotEmpty('illustrator', illustrator)
    ..putIterableIfNotEmpty('contributor', contributor)
    ..putOpt('description', description)
    ..putOpt('numberOfPages', numberOfPages)
    ..putOpt('position', position)
    ..putIterableIfNotEmpty('links', links);

  Article copyWith({
    LocalizedString? localizedName,
    String? identifier,
    AltIdentifier? altIdentifier,
    Map<String, String>? sortAs,
    List<Contributor>? author,
    List<Contributor>? translator,
    List<Contributor>? editor,
    List<Contributor>? artist,
    List<Contributor>? illustrator,
    List<Contributor>? contributor,
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
      altIdentifier: altIdentifier ?? this.altIdentifier,
      sortAs: sortAs ?? this.sortAs,
      author: author ?? this.author,
      translator: translator ?? this.translator,
      editor: editor ?? this.editor,
      artist: artist ?? this.artist,
      illustrator: illustrator ?? this.illustrator,
      contributor: contributor ?? this.contributor,
      description: description ?? this.description,
      numberOfPages: numberOfPages ?? this.numberOfPages,
      position: position ?? this.position,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }
}
