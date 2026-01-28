// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart' show Link;

class Feed extends AdditionalProperties with EquatableMixin implements JSONable {
  const Feed(
    this.metadata,
    this.links,
    this.facets,
    this.groups,
    this.publications,
    this.navigation,
    this.context,
    Map<String, dynamic>? additionalProperties,
  ) : super(additionalProperties: additionalProperties ?? const {});

  final OpdsMetadata metadata;
  final List<Link> links;
  final List<Facet> facets;
  final List<Group> groups;
  final List<OpdsPublication> publications;
  final List<Link> navigation;
  final List<String> context;

  @override
  List<Object?> get props => [metadata, links, facets, groups, publications, navigation, context, additionalProperties];

  @override
  String toString() =>
      'Feed{title: ${metadata.title}, metadata: $metadata, '
      'links: $links, facets: $facets, groups: $groups, '
      'publications: $publications, navigation: $navigation, '
      'context: $context}';

  Feed copyWith({
    OpdsMetadata? metadata,
    List<Link>? links,
    List<Facet>? facets,
    List<Group>? groups,
    List<OpdsPublication>? publications,
    List<Link>? navigation,
    List<String>? context,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Feed(
      metadata ?? this.metadata,
      links ?? this.links,
      facets ?? this.facets,
      groups ?? this.groups,
      publications ?? this.publications,
      navigation ?? this.navigation,
      context ?? this.context,
      mergeProperties,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = Map<String, dynamic>.of(additionalProperties)
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('publications', publications.toJson())
      ..put('navigation', navigation.toJson())
      ..put('links', links.toJson())
      ..put('groups', groups.toJson())
      ..put('facets', facets.toJson());
    return json;
  }

  static Feed? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final metadata = OpdsMetadata.fromJson(jsonObject.safeRemove<Map<String, dynamic>>('metadata'));
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('links'));
    final facets = Facet.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('facets'));
    final groups = Group.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('groups'));
    final publications = OpdsPublication.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('publications'));
    final navigation = Link.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('navigation'));
    final context = (jsonObject.safeRemove<List<dynamic>>('@context') ?? []).map((e) => e.toString()).toList();

    return Feed(metadata, links, facets, groups, publications, navigation, context, jsonObject);
  }
}

class FeedJsonConverter extends JsonConverter<Feed?, Map<String, dynamic>?> {
  const FeedJsonConverter();

  @override
  Feed? fromJson(Map<String, dynamic>? json) => json == null ? null : Feed.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Feed? feed) => feed?.toJson();
}
