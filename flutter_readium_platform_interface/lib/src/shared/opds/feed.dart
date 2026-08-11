// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

@immutable
class Feed extends AdditionalProperties with Equatable implements JSONable {
  const Feed({
    this.metadata = const OpdsMetadata(localizedTitle: LocalizedString()),
    this.links = const [],
    this.facets = const [],
    this.groups = const [],
    this.publications = const [],
    this.navigation = const [],
    this.context = const [],
    Map<String, dynamic>? additionalProperties = const {},
  }) : super(additionalProperties: additionalProperties ?? const {});

  static const _unset = Object();

  final OpdsMetadata metadata;
  final List<Link> links;
  final List<Facet> facets;
  final List<Group> groups;
  final List<OpdsPublication> publications;
  final List<Link> navigation;
  final List<String> context;

  @override
  List<Object?> get props => [
    metadata,
    links,
    facets,
    groups,
    publications,
    navigation,
    context,
    additionalProperties,
  ];

  @override
  String toString() =>
      'Feed{title: ${metadata.title}, metadata: $metadata, '
      'links: $links, facets: $facets, groups: $groups, '
      'publications: $publications, navigation: $navigation, '
      'context: $context}';

  Feed copyWith({
    Object? metadata = _unset,
    Object? links = _unset,
    Object? facets = _unset,
    Object? groups = _unset,
    Object? publications = _unset,
    Object? navigation = _unset,
    Object? context = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Feed(
      metadata: identical(metadata, _unset) ? this.metadata : (metadata as OpdsMetadata?)!,
      links: identical(links, _unset) ? this.links : (links as List<Link>?)!,
      facets: identical(facets, _unset) ? this.facets : (facets as List<Facet>?)!,
      groups: identical(groups, _unset) ? this.groups : (groups as List<Group>?)!,
      publications: identical(publications, _unset) ? this.publications : (publications as List<OpdsPublication>?)!,
      navigation: identical(navigation, _unset) ? this.navigation : (navigation as List<Link>?)!,
      context: identical(context, _unset) ? this.context : (context as List<String>?)!,
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
    final metadata = OpdsMetadata.fromJson(
      jsonObject.optNullableMap('metadata', remove: true),
    );
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJsonArray(
      jsonObject.optJsonArray('links', remove: true),
    );
    final facets = Facet.fromJsonArray(
      jsonObject.optJsonArray('facets', remove: true),
    );
    final groups = Group.fromJsonArray(
      jsonObject.optJsonArray('groups', remove: true),
    );
    final publications = OpdsPublication.fromJsonArray(
      jsonObject.optJsonArray('publications', remove: true),
    );
    final navigation = Link.fromJsonArray(
      jsonObject.optJsonArray('navigation', remove: true),
    );
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
