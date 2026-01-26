// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';

import '../../utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart';
import 'opds_publication.dart';

class Group with EquatableMixin implements JSONable {
  Group({required this.metadata, required this.links, this.publications = const [], this.navigation = const []});

  final OpdsMetadata metadata;
  final List<Link> links;
  final List<OpdsPublication> publications;
  final List<Link> navigation;

  @override
  List<Object?> get props => [metadata, links, publications, navigation];

  @override
  String toString() =>
      'Group{metadata: $metadata, links: $links, '
      'publications: $publications, navigation: $navigation}';

  Group copyWith({
    OpdsMetadata? metadata,
    List<Link>? links,
    List<OpdsPublication>? publications,
    List<Link>? navigation,
  }) => Group(
    metadata: metadata ?? this.metadata,
    links: links ?? this.links,
    publications: publications ?? this.publications,
    navigation: navigation ?? this.navigation,
  );

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson())
      ..put('publications', publications.toJson())
      ..put('navigation', navigation.toJson());
    return json;
  }

  static Group? fromJson(Map<String, dynamic> json) {
    final metadata = OpdsMetadata.fromJson(json['metadata'] as Map<String, dynamic>?);
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJSONArray(json['links'] as List<dynamic>?);
    final publications = OpdsPublication.fromJSONArray(json['publications'] as List<dynamic>?);
    final navigation = Link.fromJSONArray(json['navigation'] as List<dynamic>?);
    return Group(metadata: metadata, links: links, publications: publications, navigation: navigation);
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
