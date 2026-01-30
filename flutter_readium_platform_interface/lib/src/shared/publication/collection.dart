// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../publication.dart';

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
class Collection extends AdditionalProperties with EquatableMixin implements JSONable {
  const Collection({
    required this.localizedName,
    this.identifier,
    this.localizedSortAs,
    this.roles = const [],
    this.position,
    this.links = const [],
    super.additionalProperties,
  });

  /// The name of the contributor.
  final LocalizedString localizedName;

  /// (Nullable) An unambiguous reference to this contributor.
  final String? identifier;

  /// (Nullable) The string used to sort the name of the contributor.
  final LocalizedString? localizedSortAs;

  /// The role of the contributor in the publication making.
  final List<String> roles;

  /// (Nullable) The position of the publication in this collection/series, when the contributor represents a collection.
  final double? position;
  final List<Link> links;

  /// Returns the default translation string for the [localizedName].
  String get name => localizedName.string;

  /// Returns the default translation string for the [localizedSortAs].
  String? get sortAs => localizedSortAs?.string;

  @override
  List<Object?> get props => [localizedName, identifier, localizedSortAs, roles, position, links];

  @override
  String toString() => '$runtimeType($props)';

  Collection copyWith({
    LocalizedString? localizedName,
    String? identifier,
    LocalizedString? localizedSortAs,
    List<String>? roles,
    double? position,
    List<Link>? links,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Collection(
      localizedName: localizedName ?? this.localizedName,
      identifier: identifier ?? this.identifier,
      localizedSortAs: localizedSortAs ?? this.localizedSortAs,
      roles: roles?.toSet().toList() ?? this.roles,
      position: position ?? this.position,
      links: links ?? this.links,
      additionalProperties: mergeProperties,
    );
  }

  /// Serializes a [Contributor] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => {}
    ..putJSONableIfNotEmpty('name', localizedName)
    ..putOpt('identifier', identifier)
    ..putJSONableIfNotEmpty('sortAs', localizedSortAs)
    ..putIterableIfNotEmpty('role', roles)
    ..putOpt('position', position)
    ..putIterableIfNotEmpty('links', links);

  /// Parses a [Contributor] from its RWPM JSON representation.
  ///
  /// A contributor can be parsed from a single string, or a full-fledged object.
  /// The [links]' href and their children's will be normalized recursively using the
  /// provided [normalizeHref] closure.
  /// If the contributor can't be parsed, a warning will be logged with [warnings].
  static Collection? fromJson(dynamic json, {LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity}) =>
      Contributor.fromJson(json, normalizeHref: normalizeHref)?.toCollection();

  /// Creates a list of [Collection] from its RWPM JSON representation.
  ///
  /// The [links]' href and their children's will be normalized recursively using the
  /// provided [normalizeHref] closure.
  /// If a contributor can't be parsed, a warning will be logged with [warnings].
  static List<Collection> fromJsonArray(
    dynamic json, {
    LinkHrefNormalizer normalizeHref = linkHrefNormalizerIdentity,
  }) => Contributor.fromJsonArray(
    json,
    normalizeHref: normalizeHref,
  ).map((contributor) => contributor.toCollection()).toList();
}

extension ContributorExtension on Contributor {
  Collection toCollection() => Collection(
    localizedName: localizedName,
    identifier: identifier,
    localizedSortAs: localizedSortAs,
    roles: roles,
    position: position,
    links: links,
    additionalProperties: additionalProperties,
  );
}

class CollectionJsonConverter extends JsonConverter<Collection?, Map<String, dynamic>?> {
  const CollectionJsonConverter();

  @override
  Collection? fromJson(Map<String, dynamic>? json) => Collection.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Collection? collection) => collection?.toJson();
}
