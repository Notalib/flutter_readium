// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../../utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart' show Link;
import 'opds_publication.dart';

class Feed with EquatableMixin implements JSONable {
  Feed(this.metadata, this.links, this.facets, this.groups, this.publications, this.navigation, this.context);

  OpdsMetadata metadata;
  List<Link> links;
  List<Facet> facets;
  List<Group> groups;
  List<OpdsPublication> publications;
  List<Link> navigation;
  List<String> context;

  @override
  List<Object?> get props => [metadata, links, facets, groups, publications, navigation, context];

  @override
  String toString() =>
      'Feed{title: ${metadata.title}, metadata: $metadata, '
      'links: $links, facets: $facets, groups: $groups, '
      'publications: $publications, navigation: $navigation, '
      'context: $context}';

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('publications', publications.toJson())
      ..put('navigation', navigation.toJson())
      ..put('links', links.toJson())
      ..put('groups', groups.toJson())
      ..put('facets', facets.toJson());
    return json;
  }

  static Feed? fromJson(Map<String, dynamic> json) {
    final metadata = OpdsMetadata.fromJson(json['metadata'] as Map<String, dynamic>?);
    if (metadata == null) {
      return null;
    }

    return Feed(
      metadata,
      Link.fromJSONArray(json['links'] as List<dynamic>?),
      Facet.fromJSONArray(json['facets'] as List<Map<String, dynamic>>?),
      Group.fromJSONArray(json['groups'] as List<dynamic>?),
      OpdsPublication.fromJSONArray(json['publications'] as List<Map<String, dynamic>>?),
      Link.fromJSONArray(json['navigation'] as List<dynamic>?),
      (json['@context'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
