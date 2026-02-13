import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Periodical collection.
///
/// See: https://readium.org/webpub-manifest/schema/periodical.schema.json
@immutable
class Periodical extends BaseCollection {
  factory Periodical.fromJsonString(String localizedString) =>
      Periodical(localizedName: LocalizedString.fromJsonString(localizedString));
  factory Periodical.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      return Periodical.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Periodical.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      throw ArgumentError('Invalid JSON for Episode: $json');
    }
  }

  factory Periodical.fromJsonMap(
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

    final volumes = Volume.listFromJson(jsonObject.opt('volume', remove: true), normalizeHref: normalizeHref);
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true), normalizeHref: normalizeHref);

    return Periodical(
      position: position,
      localizedName: localizedName,
      identifier: identifier,
      altIdentifiers: altIdentifiers,
      localizedSortAs: localizedSortAs,
      links: links,
      issues: issues,
      volumes: volumes,
      additionalProperties: jsonObject,
    );
  }

  const Periodical({
    required super.localizedName,
    super.position,
    super.identifier,
    super.altIdentifiers,
    super.localizedSortAs,
    super.links,
    this.issues = const [],
    this.volumes = const [],
    super.additionalProperties,
  });

  final List<Issue> issues;
  final List<Volume> volumes;

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedName == null &&
        identifier == null &&
        altIdentifiers == null &&
        localizedSortAs == null &&
        (links == null || links!.isEmpty) &&
        (volumes.isEmpty)) {
      return position;
    } else {
      return <String, dynamic>{...additionalProperties}
        ..putOpt('position', position)
        ..putIterableIfNotEmpty('altIdentifier', altIdentifiers.toJsonList())
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putIterableIfNotEmpty('links', links)
        ..putOpt('volume', volumes.toSingleOrMultiJson());
    }
  }

  Periodical copyWith({
    double? position,
    LocalizedString? localizedName,
    String? identifier,
    List<AltIdentifier>? altIdentifiers,
    LocalizedString? localizedSortAs,
    List<Link>? links,
    List<Issue>? issues,
    List<Volume>? volumes,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Periodical(
      position: position ?? this.position,
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      altIdentifiers: altIdentifiers ?? this.altIdentifiers,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      links: links ?? this.links,
      issues: issues ?? this.issues,
      volumes: volumes ?? this.volumes,
      additionalProperties: mergeProperties,
    );
  }

  static List<Periodical> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Periodical.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Periodical.fromJson(json, normalizeHref: normalizeHref)];
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
    issues,
    volumes,
    additionalProperties,
  ];
}
