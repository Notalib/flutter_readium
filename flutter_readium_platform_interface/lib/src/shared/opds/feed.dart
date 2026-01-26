// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../../commons/utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart' show Link;
import 'opds_publication.dart';

class Feed with EquatableMixin implements JSONable {
  Feed(
    this.title,
    this.type,
    this.href, {
    OpdsMetadata? metadata,
    List<Link>? links,
    List<Facet>? facets,
    List<Group>? groups,
    List<OpdsPublication>? publications,
    List<Link>? navigation,
    List<String>? context,
  }) : metadata = metadata ?? OpdsMetadata(title: title),
       links = links ?? [],
       facets = facets ?? [],
       groups = groups ?? [],
       publications = publications ?? [],
       navigation = navigation ?? [],
       context = context ?? [];
  final String title;
  final int type;
  final Uri href;
  OpdsMetadata metadata;
  List<Link> links;
  List<Facet> facets;
  List<Group> groups;
  List<OpdsPublication> publications;
  List<Link> navigation;
  List<String> context;

  @override
  List<Object?> get props => [title, type, href, metadata, links, facets, groups, publications, navigation, context];

  @override
  String toString() =>
      'Feed{title: $title, type: $type, href: $href, metadata: $metadata, '
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
}
