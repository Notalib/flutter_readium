// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: must_be_immutable

import 'dart:io';

import 'package:equatable/equatable.dart';

import '../opds.dart';
import '../publication/publication.dart';

class Feed with EquatableMixin {
  Feed(
    this.title,
    this.type,
    this.href, {
    OpdsMetadata? metadata,
    List<Link>? links,
    List<Facet>? facets,
    List<Group>? groups,
    List<Publication>? publications,
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
  List<Publication> publications;
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
}

class ParseData with EquatableMixin {
  ParseData({required this.type, this.feed, this.publication});
  final Feed? feed;
  final Publication? publication;
  final int type;

  @override
  List<Object?> get props => [feed, publication, type];

  @override
  String toString() => 'ParseData{feed: $feed, publication: $publication, type: $type}';
}
