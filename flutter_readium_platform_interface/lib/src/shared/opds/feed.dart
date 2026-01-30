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
  const Feed({
    this.metadata = const OpdsMetadata(title: ''),
    this.links = const [],
    this.facets = const [],
    this.groups = const [],
    this.publications = const [],
    this.navigation = const [],
    this.context = const [],
    Map<String, dynamic>? additionalProperties = const {},
  }) : super(additionalProperties: additionalProperties ?? const {});

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
      metadata: metadata ?? this.metadata,
      links: links ?? this.links,
      facets: facets ?? this.facets,
      groups: groups ?? this.groups,
      publications: publications ?? this.publications,
      navigation: navigation ?? this.navigation,
      context: context ?? this.context,
      additionalProperties: mergeProperties,
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
    final metadata = OpdsMetadata.fromJson(jsonObject.optNullableMap('metadata', remove: true));
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true));
    final facets = Facet.fromJsonArray(jsonObject.optJsonArray('facets', remove: true));
    final groups = Group.fromJsonArray(jsonObject.optJsonArray('groups', remove: true));
    final publications = OpdsPublication.fromJsonArray(jsonObject.optJsonArray('publications', remove: true));
    final navigation = Link.fromJsonArray(jsonObject.optJsonArray('navigation', remove: true));
    final context = (jsonObject.optJsonArray('@context', remove: true) ?? []).map((e) => e.toString()).toList();

    return Feed(
      metadata: metadata,
      links: links,
      facets: facets,
      groups: groups,
      publications: publications,
      navigation: navigation,
      context: context,
      additionalProperties: jsonObject,
    );
  }
}

class FeedJsonConverter extends JsonConverter<Feed, Map<String, dynamic>?> {
  const FeedJsonConverter();

  @override
  Feed fromJson(Map<String, dynamic>? json) => Feed.fromJson(json)!;

  @override
  Map<String, dynamic>? toJson(Feed? feed) => feed?.toJson();
}
