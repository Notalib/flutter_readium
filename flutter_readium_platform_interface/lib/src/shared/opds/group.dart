// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../../utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart';
import 'opds_publication.dart';

class Group with EquatableMixin implements JSONable {
  Group({
    required this.title,
    OpdsMetadata? metadata,
    List<Link>? links,
    List<OpdsPublication>? publications,
    List<Link>? navigation,
  }) : metadata = metadata ?? OpdsMetadata(title: title),
       links = links ?? [],
       publications = publications ?? [],
       navigation = navigation ?? [];
  final String title;

  OpdsMetadata metadata;
  List<Link> links;
  List<OpdsPublication> publications;
  List<Link> navigation;

  @override
  List<Object?> get props => [title, metadata, links, publications, navigation];

  @override
  String toString() =>
      'Group{title: $title, metadata: $metadata, links: $links, '
      'publications: $publications, navigation: $navigation}';

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson())
      ..put('publications', publications.toJson())
      ..put('navigation', navigation.toJson());
    return json;
  }

  static fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? '';
    final metadata = OpdsMetadata.fromJson(json['metadata'] as Map<String, dynamic>?);
    final links = Link.fromJSONArray(json['links'] as List<dynamic>?);
    final publications = OpdsPublication.fromJSONArray(json['publications'] as List<dynamic>?);
    final navigation = Link.fromJSONArray(json['navigation'] as List<dynamic>?);
    return Group(title: title, metadata: metadata, links: links, publications: publications, navigation: navigation);
  }

  static List<Group> fromJSONArray(List<dynamic>? jsonArray) {
    if (jsonArray == null) {
      return [];
    }
    return jsonArray
        .map((json) {
          if (json is Map<String, dynamic>) {
            return Group.fromJson(json);
          }
          return null;
        })
        .whereType<Group>()
        .toList();
  }
}
