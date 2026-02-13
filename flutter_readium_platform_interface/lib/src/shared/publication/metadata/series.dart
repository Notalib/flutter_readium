import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Series collection.
///
/// See: https://readium.org/webpub-manifest/schema/series.schema.json
@immutable
class Series extends BaseCollection {
  factory Series.fromJsonString(String localizedString) =>
      Series(localizedName: LocalizedString.fromJsonString(localizedString));
  factory Series.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      return Series.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Series.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Episode: $json');
    }
  }

  factory Series.fromJsonMap(
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

    final chapters = Chapter.listFromJson(jsonObject.opt('chapter', remove: true));
    final episodes = Episode.listFromJson(jsonObject.opt('episode', remove: true));
    final seasons = Season.listFromJson(jsonObject.opt('season', remove: true));
    final storyArcs = StoryArc.listFromJson(jsonObject.opt('storyArc', remove: true));
    final volumes = Volume.listFromJson(jsonObject.opt('volume', remove: true));
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true));

    return Series(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      chapters: chapters,
      episodes: episodes,
      issues: issues,
      seasons: seasons,
      storyArcs: storyArcs,
      volumes: volumes,
      additionalProperties: jsonObject,
    );
  }

  const Series({
    required super.localizedName,
    super.position,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.chapters = const [],
    this.episodes = const [],
    this.issues = const [],
    this.seasons = const [],
    this.storyArcs = const [],
    this.volumes = const [],
    super.additionalProperties,
  });

  final List<Chapter> chapters;
  final List<Episode> episodes;
  final List<Issue> issues;
  final List<Season> seasons;
  final List<StoryArc> storyArcs;
  final List<Volume> volumes;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (chapters.isEmpty) &&
        (episodes.isEmpty) &&
        (seasons.isEmpty) &&
        (storyArcs.isEmpty) &&
        (volumes.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..putOpt('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putOpt('chapter', chapters.toSingleOrMultiJson())
        ..putOpt('episode', episodes.toSingleOrMultiJson())
        ..putOpt('season', seasons.toSingleOrMultiJson())
        ..putOpt('storyArc', storyArcs.toSingleOrMultiJson())
        ..putOpt('volume', volumes.toSingleOrMultiJson());
    }
  }

  Series copyWith({
    double? position,
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Chapter>? chapters,
    List<Episode>? episodes,
    List<Issue>? issues,
    List<Season>? seasons,
    List<StoryArc>? storyArcs,
    List<Volume>? volumes,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Series(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      chapters: chapters ?? this.chapters,
      episodes: episodes ?? this.episodes,
      issues: issues ?? this.issues,
      seasons: seasons ?? this.seasons,
      storyArcs: storyArcs ?? this.storyArcs,
      volumes: volumes ?? this.volumes,
      additionalProperties: mergeProperties,
    );
  }

  static List<Series> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Series.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Series.fromJson(json, normalizeHref: normalizeHref)];
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
    chapters,
    episodes,
    issues,
    seasons,
    storyArcs,
    volumes,
    additionalProperties,
  ];
}
