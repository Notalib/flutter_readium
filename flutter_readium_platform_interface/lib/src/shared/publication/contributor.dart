// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:dartx/dartx.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import 'collection.dart';
import 'link.dart';
import 'localized_string.dart';

/// Contributor Object for the Readium Web Publication Manifest.
/// https://readium.org/webpub-manifest/schema/contributor-object.schema.json
///
/// @param localizedName The name of the contributor.
/// @param identifier An unambiguous reference to this contributor.
/// @param sortAs The string used to sort the name of the contributor.
/// @param roles The roles of the contributor in the publication making.
/// @param position The position of the publication in this collection/series,
///     when the contributor represents a collection.
/// @param links Used to retrieve similar publications for the given contributor.
class Contributor extends Collection {
  const Contributor({
    required super.localizedName,
    super.identifier,
    super.localizedSortAs,
    super.roles,
    super.position,
    super.links,
    super.additionalProperties,
  });

  @override
  Contributor copyWith({
    LocalizedString? localizedName,
    String? identifier,
    LocalizedString? localizedSortAs,
    Set<String>? roles,
    double? position,
    List<Link>? links,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Contributor(
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      roles: roles ?? this.roles,
      position: position ?? this.position,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }

  static Contributor fromString(String name) => Contributor(localizedName: LocalizedString.fromString(name));

  /// Parses a [Contributor] from its RWPM JSON representation.
  ///
  /// A contributor can be parsed from a single string, or a full-fledged object.
  /// The [links]' href and their children's will be normalized recursively using the
  /// provided [normalizeHref] closure.
  /// If the contributor can't be parsed, a warning will be logged with [warnings].
  static Contributor? fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) {
    if (json == null) {
      return null;
    }

    var jsonObject = <String, dynamic>{};
    dynamic jsonName;
    if (json is String) {
      jsonName = json;
    } else if (json is Map<String, dynamic>) {
      jsonObject = Map<String, dynamic>.of(json);

      jsonName = jsonObject.remove('name');
    }

    if (jsonName == null || jsonName.isEmpty) {
      Fimber.i('[name] is required');
      return null;
    }

    final localizedName = LocalizedString.fromJson(jsonName);
    if (localizedName == null) {
      Fimber.i('[name] is required');
      return null;
    }

    final identifier = jsonObject.optNullableString('identifier', remove: true);
    final localizedSortAs = LocalizedString.fromJson(jsonObject.remove('sortAs'));
    final roles = jsonObject.optStringsFromArrayOrSingle('role', remove: true).toSet();
    final position = jsonObject.optNullableDouble('position', remove: true);
    final links = Link.fromJsonArray(jsonObject.optJsonArray('links'), normalizeHref: normalizeHref);

    return Contributor(
      localizedName: localizedName,
      identifier: identifier,
      localizedSortAs: localizedSortAs,
      roles: roles,
      position: position,
      links: links,
      additionalProperties: jsonObject,
    );
  }

  /// Creates a list of [Contributor] from its RWPM JSON representation.
  ///
  /// The [links]' href and their children's will be normalized recursively using the
  /// provided [normalizeHref] closure.
  /// If a contributor can't be parsed, a warning will be logged with [warnings].
  static List<Contributor> fromJsonArray(
    dynamic json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) {
    if (json is String || json is Map<String, dynamic>) {
      return [json].map((it) => Contributor.fromJson(it, normalizeHref: normalizeHref)).whereNotNull().toList();
    } else if (json is List) {
      return json.map((it) => Contributor.fromJson(it, normalizeHref: normalizeHref)).whereNotNull().toList();
    }
    return [];
  }
}

class ContributorJsonConverter extends JsonConverter<Contributor?, Map<String, dynamic>?> {
  const ContributorJsonConverter();

  @override
  Contributor? fromJson(Map<String, dynamic>? json) => Contributor.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Contributor? contributor) => contributor?.toJson();
}
