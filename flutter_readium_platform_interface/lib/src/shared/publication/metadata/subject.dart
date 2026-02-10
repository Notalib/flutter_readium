import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../../utils/jsonable.dart';
import '../../publication.dart';

/// Subject of a [Publication].
///
/// See https://github.com/readium/webpub-manifest/tree/master/contexts/default#subjects
/// https://readium.org/webpub-manifest/schema/subject.schema.json
@immutable
class Subject extends AdditionalProperties with EquatableMixin implements JSONable {
  factory Subject.fromJsonString(String name) => Subject(localizedName: LocalizedString.fromJsonString(name));

  factory Subject.fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json is String) {
      return Subject.fromJsonString(json);
    } else if (json is Map<String, dynamic>) {
      return Subject.fromJsonMap(json, normalizeHref: normalizeHref);
    } else {
      Fimber.e('Invalid JSON for Subject: $json');

      throw ArgumentError('Invalid JSON for Subject: $json');
    }
  }

  factory Subject.fromJsonMap(
    Map<String, dynamic> json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    final jsonObject = Map<String, dynamic>.of(json);
    final localizedName = LocalizedString.fromJsonDynamic(jsonObject.opt('name', remove: true));
    final localizedSortAs = LocalizedString.fromJsonDynamic(jsonObject.opt('sortAs', remove: true));
    final code = jsonObject.optNullableString('code', remove: true);
    final scheme = jsonObject.optNullableString('scheme', remove: true);
    final links = Link.fromJsonArray(jsonObject.opt('links', remove: true), normalizeHref: normalizeHref);

    if (localizedName == null) {
      throw ArgumentError('Subject must have a name: $json');
    }

    return Subject(
      localizedName: localizedName,
      localizedSortAs: localizedSortAs,
      code: code,
      scheme: scheme,
      links: links,
      additionalProperties: jsonObject,
    );
  }
  const Subject({
    required this.localizedName,
    this.localizedSortAs,
    this.code,
    this.scheme,
    this.links,
    super.additionalProperties,
  });

  final LocalizedString localizedName;
  final LocalizedString? localizedSortAs;
  final String? code;
  final String? scheme;
  final List<Link>? links;

  static List<Subject> listFromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return [];
    }

    if (json is List) {
      return json.map((e) => Subject.fromJson(e, normalizeHref: normalizeHref)).toList();
    } else if (json is Map<String, dynamic> && json.isNotEmpty) {
      return [Subject.fromJson(json, normalizeHref: normalizeHref)];
    }

    return [];
  }

  @override
  List<Object?> get props => [localizedName, localizedSortAs, code, scheme, links, additionalProperties];

  @override
  toJson() {
    if (additionalProperties.isEmpty &&
        localizedSortAs == null &&
        code == null &&
        scheme == null &&
        (links == null || links!.isEmpty)) {
      return localizedName.toJson();
    } else {
      return {...additionalProperties}
        ..putJSONableIfNotEmpty('name', localizedName)
        ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
        ..putOpt('code', code)
        ..putOpt('scheme', scheme)
        ..putIterableIfNotEmpty('links', links);
    }
  }
}

class SubjectJsonConverter implements JsonConverter<Subject, Map<String, dynamic>> {
  @override
  Subject fromJson(Map<String, dynamic> json) => Subject.fromJson(json);

  @override
  Map<String, dynamic> toJson(Subject object) => object.toJson();
}

extension ListSubjectExtension on List<Subject>? {
  dynamic toSingleOrMultiJson() {
    if (this == null || this!.isEmpty) {
      return null;
    } else if (this!.length == 1) {
      return this!.first.toJson();
    } else {
      return this!.map((e) => e.toJson()).toList();
    }
  }
}
