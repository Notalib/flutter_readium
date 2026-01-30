// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../mediatype/mediatype.dart';

/// OPDS Acquisition Object.
///
/// https://drafts.opds.io/schema/acquisition-object.schema.json
class Acquisition with EquatableMixin implements JSONable {
  const Acquisition({required this.type, this.children = const []});

  final String type;
  final List<Acquisition> children;

  /// Media type of the resource to acquire. */
  MediaType get mediaType => MediaType.parse(type) ?? MediaType.binary;

  @override
  List<Object> get props => [type, children];

  @override
  String toString() => 'Acquisition{type: $type, children: $children}';

  /// Serializes an [Acquisition] to its JSON representation.
  @override
  Map<String, dynamic> toJson() => {'type': type, if (children.isNotEmpty) 'child': children};

  /// Creates an [Acquisition] from its JSON representation.
  /// If the acquisition can't be parsed, a warning will be logged with [warnings].
  static Acquisition? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final type = jsonObject.optNullableString('type', remove: true);
    if (type == null) {
      return null;
    }

    return Acquisition(type: type, children: fromJsonArray(jsonObject.optJsonArray('child', remove: true)));
  }

  /// Creates a list of [Acquisition] from its JSON representation.
  /// If an acquisition can't be parsed, a warning will be logged with [warnings].
  static List<Acquisition> fromJsonArray(List<dynamic>? json) =>
      json?.parseObjects((it) => Acquisition.fromJson(it as Map<String, dynamic>?)) ?? [];
}

class AcquisitionJsonConverter extends JsonConverter<Acquisition?, Map<String, dynamic>?> {
  const AcquisitionJsonConverter();

  @override
  Acquisition? fromJson(Map<String, dynamic>? json) => Acquisition.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Acquisition? acquisition) => acquisition?.toJson();
}
