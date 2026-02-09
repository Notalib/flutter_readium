import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

@immutable
class StoryArc extends BaseCollection {
  factory StoryArc.fromJsonNumber(int number) =>
      StoryArc(localizedName: LocalizedString.fromJsonString(number.toString()), position: number);
  factory StoryArc.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is int) {
      return StoryArc.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return StoryArc.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for StoryArc: $json');
    }
  }

  factory StoryArc.fromJsonMap(
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
    final chapters = Chapter.listFromJson(jsonObject.opt('chapter', remove: true));
    final episodes = Episode.listFromJson(jsonObject.opt('episode', remove: true));
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true));

    return StoryArc(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifier: altIdentifier,
      localizedSortAs: localizedSortAs,
      links: links,
      chapters: chapters,
      episodes: episodes,
      issues: issues,
      additionalProperties: jsonObject,
    );
  }

  const StoryArc({
    required super.localizedName,
    this.position,
    super.identifier,
    super.altIdentifier,
    super.localizedSortAs,
    super.links,
    this.chapters = const [],
    this.episodes = const [],
    this.issues = const [],
    super.additionalProperties,
  });

  final int? position;
  final List<Chapter> chapters;
  final List<Episode> episodes;
  final List<Issue> issues;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifier == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (chapters.isEmpty) &&
        (episodes.isEmpty) &&
        (issues.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..put('position', position)
        ..putOpt('identifier', identifier)
        ..putJSONableIfNotEmpty('altIdentifier', altIdentifier)
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putIterableIfNotEmpty('chapter', chapters)
        ..putIterableIfNotEmpty('episode', episodes)
        ..putIterableIfNotEmpty('issue', issues);
    }
  }

  StoryArc copyWith({
    int? position,
    LocalizedString? localizedName,
    String? identifier,
    AltIdentifier? altIdentifier,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Chapter>? chapters,
    List<Episode>? episodes,
    List<Issue>? issues,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return StoryArc(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifier: altIdentifier ?? this.altIdentifier,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      chapters: chapters ?? this.chapters,
      episodes: episodes ?? this.episodes,
      issues: issues ?? this.issues,
      additionalProperties: mergeProperties,
    );
  }

  static List<StoryArc> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => StoryArc.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else {
      return [StoryArc.fromJson(json, normalizeHref: normalizeHref)];
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
    chapters,
    episodes,
    issues,
    additionalProperties,
  ];
}
