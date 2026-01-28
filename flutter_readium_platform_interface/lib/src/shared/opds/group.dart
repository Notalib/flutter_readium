// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../opds.dart';
import '../publication/link.dart';

class Group with EquatableMixin implements JSONable {
  const Group({required this.metadata, required this.links, this.publications = const [], this.navigation = const []});

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

  static Group? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final metadata = OpdsMetadata.fromJson(jsonObject.safeRemove<Map<String, dynamic>>('metadata'));
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('links'));
    final publications = OpdsPublication.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('publications'));
    final navigation = Link.fromJSONArray(jsonObject.safeRemove<List<dynamic>>('navigation'));
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

class GroupJsonConverter extends JsonConverter<Group?, Map<String, dynamic>?> {
  const GroupJsonConverter();

  @override
  Group? fromJson(Map<String, dynamic>? json) => json == null ? null : Group.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Group? group) => group?.toJson();
}
