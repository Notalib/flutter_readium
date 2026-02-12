// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:dfunc/dfunc.dart';
import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// https://readium.org/webpub-manifest/schema/metadata.schema.json
///
/// @param readingProgression WARNING: This contains the reading progression as declared in the
///     publication, so it might be [ReadingProgression.auto]. To lay out the content, use [effectiveReadingProgression]
///     to get the calculated reading progression from the declared direction and the language.
/// @param additionalProperties Additional metadata for extensions, as a JSON dictionary.
@immutable
class Metadata extends AdditionalProperties with EquatableMixin implements JSONable {
  const Metadata({
    required this.localizedTitle,
    this.identifier,
    this.rdfType,
    this.conformsTo,
    this.localizedSubtitle,
    this.accessibility,
    this.modified,
    this.published,
    this.languages = const [],
    this.localizedSortAs,
    this.subjects = const [],
    this.authors = const [],
    this.contributors = const [],
    this.translators = const [],
    this.editors = const [],
    this.artists = const [],
    this.illustrators = const [],
    this.letterers = const [],
    this.pencilers = const [],
    this.colorists = const [],
    this.inkers = const [],
    this.narrators = const [],
    this.publishers = const [],
    this.imprints = const [],
    this.description,
    this.duration,
    this.numberOfPages,
    this.layout,
    this.belongsTo = const BelongsTo(),
    this.tdm,
    this.readingProgression = ReadingProgression.auto,
    this.rendition,
    this.altIdentifiers,
    this.contains = const MetadataContains(),
    super.additionalProperties,
  });

  /// An URI used as the unique identifier for this [Publication].
  final String? identifier; // nullable
  final String? rdfType; // nullable
  final List<String>? conformsTo; // nullable

  final LocalizedString localizedTitle;
  final LocalizedString? localizedSubtitle; // nullable

  final Accessibility? accessibility; // nullable
  final DateTime? modified; // nullable
  final DateTime? published; // nullable

  /// Languages used in the publication.
  final List<String> languages; // BCP 47 tag

  /// Alternative title to be used for sorting the publication in the library.
  final LocalizedString? localizedSortAs; // nullable

  /// Themes/subjects of the publication.
  final List<Subject> subjects;

  final List<Contributor> authors;
  final List<Contributor> publishers;
  final List<Contributor> contributors;
  final List<Contributor> translators;
  final List<Contributor> editors;
  final List<Contributor> artists;
  final List<Contributor> illustrators;
  final List<Contributor> letterers;
  final List<Contributor> pencilers;
  final List<Contributor> colorists;
  final List<Contributor> inkers;
  final List<Contributor> narrators;
  final List<Contributor> imprints;

  final String? description; // nullable
  final double? duration; // nullable

  final String? layout;

  /// Number of pages in the publication, if available.
  final int? numberOfPages; // nullable

  final BelongsTo belongsTo;

  /// Direction of the [Publication] reading progression.
  final ReadingProgression readingProgression;

  /// Information about the contents rendition.
  final Presentation? rendition; // nullable if not an EPUB [Publication]

  final TDM? tdm;

  ReadingProgression get effectiveReadingProgression {
    if (readingProgression != ReadingProgression.auto) {
      return readingProgression;
    }

    // https://github.com/readium/readium-css/blob/develop/docs/CSS16-internationalization.md#missing-page-progression-direction
    if (languages.length != 1) {
      return ReadingProgression.ltr;
    }

    var language = languages.first.toLowerCase();

    if (language == 'zh-hant' || language == 'zh-tw') {
      return ReadingProgression.rtl;
    }

    // The region is ignored for ar, fa and he.
    language = language.split('-').first;
    if (['ar', 'fa', 'he'].contains(language)) {
      return ReadingProgression.rtl;
    }
    return ReadingProgression.ltr;
  }

  /// Returns the default translation string for the [localizedTitle].
  String get title => localizedTitle.string;

  /// Returns the default translation string for the [localizedSortAs].
  String? get sortAs => localizedSortAs?.string;

  final List<AltIdentifier>? altIdentifiers;

  final MetadataContains contains;

  @override
  List<Object?> get props => [
    identifier,
    rdfType,
    conformsTo,
    localizedTitle,
    localizedSubtitle,
    modified,
    accessibility,
    published,
    languages,
    localizedSortAs,
    subjects,
    authors,
    translators,
    editors,
    artists,
    illustrators,
    letterers,
    pencilers,
    colorists,
    inkers,
    narrators,
    contributors,
    publishers,
    imprints,
    readingProgression,
    altIdentifiers,
    description,
    duration,
    numberOfPages,
    belongsTo,
    rendition,
    contains,
    layout,
    tdm,
    additionalProperties,
  ];

  /// Serializes a [Metadata] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => Map.from(additionalProperties)
    ..putOpt('identifier', identifier)
    ..putOpt('@type', rdfType)
    ..putIterableIfNotEmpty('conformsTo', conformsTo)
    ..putJSONableIfNotEmpty('title', localizedTitle)
    ..putJSONableIfNotEmpty('subtitle', localizedSubtitle)
    ..putOpt('modified', modified?.toIso8601String())
    ..putOpt('published', published?.toIso8601String())
    ..putIterableIfNotEmpty('language', languages)
    ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
    ..put('subject', subjects.toSingleOrMultiJson())
    ..putOpt('author', authors.toSingleOrMultiJson())
    ..putOpt('translator', translators.toSingleOrMultiJson())
    ..putOpt('editor', editors.toSingleOrMultiJson())
    ..putOpt('artist', artists.toSingleOrMultiJson())
    ..putOpt('illustrator', illustrators.toSingleOrMultiJson())
    ..putOpt('letterer', letterers.toSingleOrMultiJson())
    ..putOpt('penciler', pencilers.toSingleOrMultiJson())
    ..putOpt('colorist', colorists.toSingleOrMultiJson())
    ..putOpt('inker', inkers.toSingleOrMultiJson())
    ..putOpt('narrator', narrators.toSingleOrMultiJson())
    ..putOpt('contributor', contributors.toSingleOrMultiJson())
    ..putOpt('publisher', publishers.toSingleOrMultiJson())
    ..putOpt('imprint', imprints.toSingleOrMultiJson())
    ..putOpt('readingProgression', readingProgression.name)
    ..putOpt('description', description)
    ..putOpt('duration', duration)
    ..putOpt('numberOfPages', numberOfPages)
    ..putOpt('layout', layout)
    ..putJSONableIfNotEmpty('belongsTo', belongsTo)
    ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
    ..putJSONableIfNotEmpty('contains', contains)
    ..putJSONableIfNotEmpty('tdm', tdm);

  /// Parses a [Metadata] from its RWPM JSON representation.
  ///
  /// If the metadata can't be parsed, a warning will be logged with [warnings].
  static Metadata? fromJson(
    Map<String, dynamic>? json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    var localizedTitle = LocalizedString.fromJsonDynamic(jsonObject.opt('title', remove: true));
    if (localizedTitle == null) {
      Fimber.i('[title] is missing $json');
      localizedTitle = LocalizedString.fromJsonString(''); // Fallback to an empty title
    }
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final type = jsonObject.optNullableString('@type', remove: true);
    final localizedSubtitle = LocalizedString.fromJsonDynamic(jsonObject.opt('subtitle', remove: true));
    final modified = (jsonObject.optNullableString('modified', remove: true))?.iso8601ToDate();
    final published = (jsonObject.optNullableString('published', remove: true))?.iso8601ToDate();
    final accessibility = jsonObject
        .optNullableMap('accessibility', remove: true)
        ?.let((it) => Accessibility.fromJson(it));

    final languages = jsonObject.optStringsFromArrayOrSingle('language', remove: true);
    final conformsTo = jsonObject.optStringsFromArrayOrSingle('conformsTo', remove: true);
    final localizedSortAs = LocalizedString.fromJsonDynamic(jsonObject.opt('sortAs', remove: true));
    final subjects = Subject.listFromJson(jsonObject.opt('subject', remove: true), normalizeHref: normalizeHref);
    final authors = Contributor.listFromJson(jsonObject.opt('author', remove: true), normalizeHref: normalizeHref);
    final translators = Contributor.listFromJson(
      jsonObject.opt('translator', remove: true),
      normalizeHref: normalizeHref,
    );
    final editors = Contributor.listFromJson(jsonObject.opt('editor', remove: true), normalizeHref: normalizeHref);
    final artists = Contributor.listFromJson(jsonObject.opt('artist', remove: true), normalizeHref: normalizeHref);
    final illustrators = Contributor.listFromJson(
      jsonObject.opt('illustrator', remove: true),
      normalizeHref: normalizeHref,
    );
    final letterers = Contributor.listFromJson(jsonObject.opt('letterer', remove: true), normalizeHref: normalizeHref);
    final pencilers = Contributor.listFromJson(jsonObject.opt('penciler', remove: true), normalizeHref: normalizeHref);
    final colorists = Contributor.listFromJson(jsonObject.opt('colorist', remove: true), normalizeHref: normalizeHref);
    final inkers = Contributor.listFromJson(jsonObject.opt('inker', remove: true), normalizeHref: normalizeHref);
    final narrators = Contributor.listFromJson(jsonObject.opt('narrator', remove: true), normalizeHref: normalizeHref);
    final contributors = Contributor.listFromJson(
      jsonObject.opt('contributor', remove: true),
      normalizeHref: normalizeHref,
    );
    final publishers = Contributor.listFromJson(
      jsonObject.opt('publisher', remove: true),
      normalizeHref: normalizeHref,
    );
    final imprints = Contributor.listFromJson(jsonObject.opt('imprint', remove: true), normalizeHref: normalizeHref);
    final readingProgression = ReadingProgression.fromString(
      jsonObject.optNullableString('readingProgression', remove: true),
    );
    final description = jsonObject.optNullableString('description', remove: true);
    final duration = jsonObject.optPositiveDouble('duration', remove: true);
    final numberOfPages = jsonObject.optPositiveInt('numberOfPages', remove: true);
    final contains =
        jsonObject
            .optNullableMap('contains', remove: true)
            ?.let((it) => MetadataContains.fromJson(it, normalizeHref: normalizeHref)) ??
        MetadataContains();

    final belongsToJson =
        (jsonObject.optNullableMap('belongsTo', remove: true) ??
        jsonObject.optNullableMap('belongs_to', remove: true) ??
        {});
    final belongsTo = BelongsTo.fromJson(belongsToJson, normalizeHref: normalizeHref);

    final altIdentifiers = AltIdentifier.listFromJson(jsonObject.opt('altIdentifier', remove: true));

    final tdm = TDM.fromJson(jsonObject.optNullableMap('tdm', remove: true));

    return Metadata(
      identifier: identifier,
      rdfType: type,
      conformsTo: conformsTo,
      localizedTitle: localizedTitle,
      localizedSubtitle: localizedSubtitle,
      localizedSortAs: localizedSortAs,
      modified: modified,
      accessibility: accessibility,
      published: published,
      languages: languages,
      subjects: subjects,
      authors: authors,
      translators: translators,
      editors: editors,
      artists: artists,
      illustrators: illustrators,
      letterers: letterers,
      pencilers: pencilers,
      colorists: colorists,
      inkers: inkers,
      narrators: narrators,
      contributors: contributors,
      publishers: publishers,
      imprints: imprints,
      readingProgression: readingProgression,
      description: description,
      duration: duration,
      numberOfPages: numberOfPages,
      belongsTo: belongsTo,
      contains: contains,
      tdm: tdm,
      altIdentifiers: altIdentifiers,
      additionalProperties: jsonObject,
    );
  }

  Metadata copyWith({
    String? identifier,
    String? rdfType,
    LocalizedString? localizedTitle,
    LocalizedString? localizedSubtitle,
    DateTime? modified,
    DateTime? published,
    List<String>? languages,
    LocalizedString? localizedSortAs,
    List<Subject>? subjects,
    List<Contributor>? authors,
    List<Contributor>? publishers,
    List<Contributor>? contributors,
    List<Contributor>? translators,
    List<Contributor>? editors,
    List<Contributor>? artists,
    List<Contributor>? illustrators,
    List<Contributor>? letterers,
    List<Contributor>? pencilers,
    List<Contributor>? colorists,
    List<Contributor>? inkers,
    List<Contributor>? narrators,
    List<Contributor>? imprints,
    String? description,
    double? duration,
    int? numberOfPages,
    BelongsTo? belongsTo,
    TDM? tdm,
    ReadingProgression? readingProgression,
    Presentation? rendition,
    List<AltIdentifier>? altIdentifiers,
    MetadataContains? contains,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Metadata(
      identifier: identifier ?? this.identifier,
      rdfType: rdfType ?? this.rdfType,
      localizedTitle: localizedTitle ?? this.localizedTitle,
      localizedSubtitle: localizedSubtitle ?? this.localizedSubtitle,
      modified: modified ?? this.modified,
      published: published ?? this.published,
      languages: languages ?? this.languages,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      subjects: subjects ?? this.subjects,
      authors: authors ?? this.authors,
      publishers: publishers ?? this.publishers,
      contributors: contributors ?? this.contributors,
      translators: translators ?? this.translators,
      editors: editors ?? this.editors,
      artists: artists ?? this.artists,
      illustrators: illustrators ?? this.illustrators,
      letterers: letterers ?? this.letterers,
      pencilers: pencilers ?? this.pencilers,
      colorists: colorists ?? this.colorists,
      inkers: inkers ?? this.inkers,
      narrators: narrators ?? this.narrators,
      imprints: imprints ?? this.imprints,
      description: description ?? this.description,
      duration: duration ?? this.duration,
      numberOfPages: numberOfPages ?? this.numberOfPages,
      belongsTo: belongsTo ?? this.belongsTo,
      readingProgression: readingProgression ?? this.readingProgression,
      rendition: rendition ?? this.rendition,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      contains: contains ?? this.contains,
      tdm: tdm ?? this.tdm,
      additionalProperties: mergeProperties,
    );
  }

  @override
  String toString() => 'Metadata($props)';
}

@immutable
class MetadataContains extends AdditionalProperties with EquatableMixin implements JSONable {
  factory MetadataContains.fromJson(
    Map<String, dynamic>? json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.of(json ?? {});
    final article = Article.listFromJson(jsonObject.opt('article', remove: true), normalizeHref: normalizeHref);
    final chapters = Chapter.listFromJson(jsonObject.opt('chapter', remove: true), normalizeHref: normalizeHref);
    final episodes = Episode.listFromJson(jsonObject.opt('episode', remove: true), normalizeHref: normalizeHref);
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true), normalizeHref: normalizeHref);
    final seasons = Season.listFromJson(jsonObject.opt('season', remove: true), normalizeHref: normalizeHref);
    final series = Series.listFromJson(jsonObject.opt('series', remove: true), normalizeHref: normalizeHref);
    final storyArcs = StoryArc.listFromJson(jsonObject.opt('storyArc', remove: true), normalizeHref: normalizeHref);
    final volumes = Volume.listFromJson(jsonObject.opt('volume', remove: true), normalizeHref: normalizeHref);

    return MetadataContains(
      articles: article,
      chapters: chapters,
      episodes: episodes,
      issues: issues,
      seasons: seasons,
      series: series,
      storyArcs: storyArcs,
      volumes: volumes,
      additionalProperties: jsonObject,
    );
  }

  const MetadataContains({
    this.articles = const [],
    this.chapters = const [],
    this.episodes = const [],
    this.issues = const [],
    this.seasons = const [],
    this.series = const [],
    this.storyArcs = const [],
    this.volumes = const [],
    super.additionalProperties,
  });

  final List<Article> articles;
  final List<Chapter> chapters;
  final List<Episode> episodes;
  final List<Issue> issues;
  final List<Season> seasons;
  final List<Series> series;
  final List<StoryArc> storyArcs;
  final List<Volume> volumes;

  @override
  List<Object?> get props => [
    articles,
    chapters,
    episodes,
    issues,
    seasons,
    series,
    storyArcs,
    volumes,
    additionalProperties,
  ];

  @override
  Map<String, dynamic> toJson() => {...additionalProperties}
    ..putOpt('article', articles.toSingleOrMultiJson())
    ..putOpt('chapter', chapters.toSingleOrMultiJson())
    ..putOpt('episode', episodes.toSingleOrMultiJson())
    ..putOpt('issue', issues.toSingleOrMultiJson())
    ..putOpt('season', seasons.toSingleOrMultiJson())
    ..putOpt('series', series.toSingleOrMultiJson())
    ..putOpt('storyArc', storyArcs.toSingleOrMultiJson())
    ..putOpt('volume', volumes.toSingleOrMultiJson());

  MetadataContains copyWith({
    List<Article>? articles,
    List<Chapter>? chapters,
    List<Episode>? episodes,
    List<Issue>? issues,
    List<Season>? seasons,
    List<Series>? series,
    List<StoryArc>? storyArcs,
    List<Volume>? volumes,
  }) => MetadataContains(
    articles: articles ?? this.articles,
    chapters: chapters ?? this.chapters,
    episodes: episodes ?? this.episodes,
    issues: issues ?? this.issues,
    seasons: seasons ?? this.seasons,
    series: series ?? this.series,
    storyArcs: storyArcs ?? this.storyArcs,
    volumes: volumes ?? this.volumes,
    additionalProperties: additionalProperties,
  );
}

class MetadataJsonConverter extends JsonConverter<Metadata?, Map<String, dynamic>?> {
  const MetadataJsonConverter();

  @override
  Metadata? fromJson(Map<String, dynamic>? json) => Metadata.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Metadata? metadata) => metadata?.toJson();
}
