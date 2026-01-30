// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:dartx/dartx.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../opds.dart' show OpdsMetadata;
import '../publication/link.dart' show Link;

class Facet with EquatableMixin implements JSONable {
  const Facet({required this.metadata, required this.links});

  final OpdsMetadata metadata;
  final List<Link> links;

  @override
  List<Object> get props => [metadata, links];

  @override
  String toString() => 'Facet{metadata: $metadata, links: $links}';

  Facet copyWith({OpdsMetadata? metadata, List<Link>? links}) =>
      Facet(metadata: metadata ?? this.metadata, links: links ?? this.links);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson());
    return json;
  }

  static Facet? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final metadata = OpdsMetadata.fromJson(jsonObject.optNullableMap('metadata', remove: true));
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true));
    return Facet(metadata: metadata, links: links);
  }

  static List<Facet> fromJsonArray(List<dynamic>? jsonArray) {
    if (jsonArray == null) {
      return [];
    }
    return jsonArray.mapNotNull((json) {
      if (json is Map<String, dynamic>) {
        return Facet.fromJson(json);
      }
      return null;
    }).toList();
  }
}

class FacetJsonConverter extends JsonConverter<Facet?, Map<String, dynamic>?> {
  const FacetJsonConverter();

  @override
  Facet? fromJson(Map<String, dynamic>? json) => json == null ? null : Facet.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Facet? facet) => facet?.toJson();
}
