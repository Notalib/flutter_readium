// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../extensions/strings.dart';
import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../epub.dart';
import 'collection.dart';
import 'contributor.dart';
import 'link.dart';
import 'localized_string.dart';
import 'reading_progression.dart';
import 'subject.dart';
import 'publication.dart';

export 'presentation/presentation_metadata_extension.dart';
export '../../utils/additional_properties.dart';
export 'epub/metadata_extension.dart';

/// https://readium.org/webpub-manifest/schema/metadata.schema.json
///
/// @param readingProgression WARNING: This contains the reading progression as declared in the
///     publication, so it might be [ReadingProgression.AUTO]. To lay out the content, use [effectiveReadingProgression]
///     to get the calculated reading progression from the declared direction and the language.
/// @param additionalProperties Additional metadata for extensions, as a JSON dictionary.
class Metadata extends AdditionalProperties with EquatableMixin implements JSONable {
  Metadata({
    required this.localizedTitle,
    this.identifier,
    this.rdfType,
    this.conformsTo,
    this.localizedSubtitle,
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
    this.belongsTo = const {},
    this.belongsToCollections = const [],
    this.belongsToSeries = const [],
    this.readingProgression = ReadingProgression.auto,
    this.rendition,
    super.additionalProperties,
  }) {
    if (belongsToCollections.isNotEmpty) {
      belongsTo['collection'] = belongsToCollections;
    }
    if (belongsToSeries.isNotEmpty) {
      belongsTo['series'] = belongsToSeries;
    }
  }

  /// An URI used as the unique identifier for this [Publication].
  final String? identifier; // nullable
  final String? rdfType; // nullable
  final List<String>? conformsTo; // nullable

  final LocalizedString localizedTitle;
  final LocalizedString? localizedSubtitle; // nullable
  final DateTime? modified; // nullable
  final DateTime? published; // nullable

  /// Languages used in the publication.
  final List<String> languages; // BCP 47 tag

  /// (Nullable) First language in the publication.
  String? get language => (languages.isNotEmpty ? languages.first : null);

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

  /// Number of pages in the publication, if available.
  final int? numberOfPages; // nullable

  // TODO: belongsTo should be a propert
  final Map<String, List<Collection>> belongsTo;
  final List<Collection> belongsToCollections;
  final List<Collection> belongsToSeries;

  /// Direction of the [Publication] reading progression.
  final ReadingProgression readingProgression;

  /// Information about the contents rendition.
  final Presentation? rendition; // nullable if not an EPUB [Publication]

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

  @override
  List<Object?> get props => [
    identifier,
    rdfType,
    conformsTo,
    localizedTitle,
    localizedSubtitle,
    modified,
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
    description,
    duration,
    numberOfPages,
    belongsTo,
    rendition,
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
    ..putIterableIfNotEmpty('subject', subjects)
    ..putIterableIfNotEmpty('author', authors)
    ..putIterableIfNotEmpty('translator', translators)
    ..putIterableIfNotEmpty('editor', editors)
    ..putIterableIfNotEmpty('artist', artists)
    ..putIterableIfNotEmpty('illustrator', illustrators)
    ..putIterableIfNotEmpty('letterer', letterers)
    ..putIterableIfNotEmpty('penciler', pencilers)
    ..putIterableIfNotEmpty('colorist', colorists)
    ..putIterableIfNotEmpty('inker', inkers)
    ..putIterableIfNotEmpty('narrator', narrators)
    ..putIterableIfNotEmpty('contributor', contributors)
    ..putIterableIfNotEmpty('publisher', publishers)
    ..putIterableIfNotEmpty('imprint', imprints)
    ..putOpt('readingProgression', readingProgression.value)
    ..putOpt('description', description)
    ..putOpt('duration', duration)
    ..putOpt('numberOfPages', numberOfPages)
    ..putMapIfNotEmpty('belongsTo', belongsTo);

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

    var localizedTitle = LocalizedString.fromJson(jsonObject.remove('title'));
    if (localizedTitle == null) {
      Fimber.i('[title] is missing $json');
      localizedTitle = LocalizedString.fromString(''); // Fallback to an empty title
    }
    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final type = jsonObject.optNullableString('@type', remove: true);
    final localizedSubtitle = LocalizedString.fromJson(jsonObject.remove('subtitle'));
    final modified = (jsonObject.remove('modified') as String?)?.iso8601ToDate();
    final published = (jsonObject.remove('published') as String?)?.iso8601ToDate();
    final languages = jsonObject.optStringsFromArrayOrSingle('language', remove: true);
    final conformsTo = jsonObject.optStringsFromArrayOrSingle('conformsTo', remove: true);
    final localizedSortAs = LocalizedString.fromJson(jsonObject.remove('sortAs'));
    final subjects = Subject.fromJsonArray(jsonObject.remove('subject'), normalizeHref: normalizeHref);
    final authors = Contributor.fromJsonArray(jsonObject.remove('author'), normalizeHref: normalizeHref);
    final translators = Contributor.fromJsonArray(jsonObject.remove('translator'), normalizeHref: normalizeHref);
    final editors = Contributor.fromJsonArray(jsonObject.remove('editor'), normalizeHref: normalizeHref);
    final artists = Contributor.fromJsonArray(jsonObject.remove('artist'), normalizeHref: normalizeHref);
    final illustrators = Contributor.fromJsonArray(jsonObject.remove('illustrator'), normalizeHref: normalizeHref);
    final letterers = Contributor.fromJsonArray(jsonObject.remove('letterer'), normalizeHref: normalizeHref);
    final pencilers = Contributor.fromJsonArray(jsonObject.remove('penciler'), normalizeHref: normalizeHref);
    final colorists = Contributor.fromJsonArray(jsonObject.remove('colorist'), normalizeHref: normalizeHref);
    final inkers = Contributor.fromJsonArray(jsonObject.remove('inker'), normalizeHref: normalizeHref);
    final narrators = Contributor.fromJsonArray(jsonObject.remove('narrator'), normalizeHref: normalizeHref);
    final contributors = Contributor.fromJsonArray(jsonObject.remove('contributor'), normalizeHref: normalizeHref);
    final publishers = Contributor.fromJsonArray(jsonObject.remove('publisher'), normalizeHref: normalizeHref);
    final imprints = Contributor.fromJsonArray(jsonObject.remove('imprint'), normalizeHref: normalizeHref);
    final readingProgression = ReadingProgression.fromValue(jsonObject.remove('readingProgression') as String?);
    final description = jsonObject.remove('description') as String?;
    final duration = jsonObject.optPositiveDouble('duration', remove: true);
    final numberOfPages = jsonObject.optPositiveInt('numberOfPages', remove: true);

    final belongsToJson =
        (jsonObject.optNullableMap('belongsTo', remove: true) ??
        jsonObject.optNullableMap('belongs_to', remove: true) ??
        {});
    final belongsTo = <String, List<Collection>>{};
    for (final key in belongsToJson.keys) {
      if (!belongsToJson.isNull(key)) {
        final dynamic value = belongsToJson[key];
        belongsTo[key] = Contributor.fromJsonArray(value, normalizeHref: normalizeHref);
      }
    }

    return Metadata(
      identifier: identifier,
      rdfType: type,
      conformsTo: conformsTo,
      localizedTitle: localizedTitle,
      localizedSubtitle: localizedSubtitle,
      localizedSortAs: localizedSortAs,
      modified: modified,
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
      additionalProperties: json,
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
    Map<String, List<Collection>>? belongsTo,
    ReadingProgression? readingProgression,
    Presentation? rendition,
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
      additionalProperties: mergeProperties,
    );
  }

  @override
  String toString() => 'Metadata($props)';
}

class MetadataJsonConverter extends JsonConverter<Metadata?, Map<String, dynamic>?> {
  const MetadataJsonConverter();

  @override
  Metadata? fromJson(Map<String, dynamic>? json) => Metadata.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Metadata? metadata) => metadata?.toJson();
}
