// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../utils/jsonable.dart';

/// Library-specific features when a specific book is unavailable but provides a hold list.
///
/// https://drafts.opds.io/schema/properties.schema.json
@immutable
class Holds with EquatableMixin implements JSONable {
  const Holds({this.total, this.position});
  final double? total;
  final double? position;

  @override
  List<Object?> get props => [total, position];

  /// Serializes an [Holds] to its JSON representation.
  @override
  Map<String, dynamic> toJson() => {}
    ..putOpt('total', total)
    ..putOpt('position', position);

  /// Creates an [Holds] from its JSON representation.
  static Holds? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    return Holds(
      total: jsonObject.optPositiveDouble('total', remove: true),
      position: jsonObject.optPositiveDouble('position', remove: true),
    );
  }
}

class HoldsJsonConverter extends JsonConverter<Holds?, Map<String, dynamic>?> {
  const HoldsJsonConverter();

  @override
  Holds? fromJson(Map<String, dynamic>? json) => Holds.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Holds? holds) => holds?.toJson();
}
