import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

@immutable
class Volume extends BaseCollection {
  factory Volume.fromJsonNumber(int number) => Volume(position: number);
  factory Volume.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is int) {
      return Volume.fromJsonNumber(json);
    } else if (json is Map<String, dynamic>) {
      return Volume.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Volume: $json');
    }
  }

  factory Volume.fromJsonMap(
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
    final chapters = Chapter.listFromJson(jsonObject.opt('chapter', remove: true), normalizeHref: normalizeHref);
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true), normalizeHref: normalizeHref);
    final storyArcs = StoryArc.listFromJson(jsonObject.opt('storyArc', remove: true), normalizeHref: normalizeHref);

    return Volume(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifier: altIdentifier,
      localizedSortAs: localizedSortAs,
      links: links,
      additionalProperties: jsonObject,
      chapters: chapters,
      issues: issues,
      storyArcs: storyArcs,
    );
  }

  const Volume({
    required this.position,
    super.localizedName,
    super.identifier,
    super.altIdentifier,
    super.localizedSortAs,
    super.links,
    this.chapters = const [],
    this.issues = const [],
    this.storyArcs = const [],
    super.additionalProperties,
  });

  final int position;
  final List<Chapter> chapters;
  final List<Issue> issues;
  final List<StoryArc> storyArcs;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifier == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty)) {
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
        ..putIterableIfNotEmpty('issue', issues)
        ..putIterableIfNotEmpty('storyArc', storyArcs);
    }
  }

  Volume copyWith({
    int? position,
    LocalizedString? localizedName,
    String? identifier,
    AltIdentifier? altIdentifier,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Chapter>? chapters,
    List<Issue>? issues,
    List<StoryArc>? storyArcs,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Volume(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifier: altIdentifier ?? this.altIdentifier,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      chapters: chapters ?? this.chapters,
      issues: issues ?? this.issues,
      storyArcs: storyArcs ?? this.storyArcs,
      additionalProperties: mergeProperties,
    );
  }

  static List<Volume> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Volume.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else {
      return [Volume.fromJson(json, normalizeHref: normalizeHref)];
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
    issues,
    storyArcs,
    additionalProperties,
  ];
}
