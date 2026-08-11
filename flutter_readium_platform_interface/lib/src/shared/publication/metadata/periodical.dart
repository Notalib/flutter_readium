import 'package:meta/meta.dart';
import '../../../../flutter_readium_platform_interface.dart';
import 'base_collection.dart';

/// Periodical collection.
///
/// See: https://readium.org/webpub-manifest/schema/periodical.schema.json
@immutable
class Periodical extends BaseCollection {
  factory Periodical.fromJsonString(String localizedString) => Periodical(
    localizedName: LocalizedString.fromJsonString(localizedString),
  );
  factory Periodical.fromJson(dynamic json) {
    if (json is String) {
      return Periodical.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Periodical.fromJsonMap(json);
    } else {
      throw ArgumentError('Invalid JSON for Episode: $json');
    }
  }

  factory Periodical.fromJsonMap(Map<String, dynamic> json) {
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

    final volumes = Volume.listFromJson(jsonObject.opt('volume', remove: true));
    final issues = Issue.listFromJson(jsonObject.opt('issue', remove: true));

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

  static const _unset = Object();

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
    Object? position = _unset,
    Object? localizedName = _unset,
    Object? identifier = _unset,
    Object? altIdentifiers = _unset,
    Object? localizedSortAs = _unset,
    Object? links = _unset,
    Object? issues = _unset,
    Object? volumes = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Periodical(
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
      issues: identical(issues, _unset) ? this.issues : (issues as List<Issue>?)!,
      volumes: identical(volumes, _unset) ? this.volumes : (volumes as List<Volume>?)!,
      additionalProperties: mergeProperties,
    );
  }

  static List<Periodical> listFromJson(dynamic json) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Periodical.fromJson(e)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Periodical.fromJson(json)];
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
