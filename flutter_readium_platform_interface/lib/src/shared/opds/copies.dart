// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';

/// Library-specific feature that contains information about the copies that a library has acquired.
///
/// https://drafts.opds.io/schema/properties.schema.json
class Copies with EquatableMixin implements JSONable {
  const Copies({this.total, this.available});
  final int? total;
  final int? available;

  @override
  List<Object?> get props => [total, available];

  /// Serializes an [Copies] to its JSON representation.
  @override
  Map<String, dynamic> toJson() => {if (total != null) 'total': total, if (available != null) 'available': available};

  /// Creates an [Copies] from its JSON representation.
  static Copies? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    return Copies(
      total: jsonObject.optPositiveInt('total', remove: true),
      available: jsonObject.optPositiveInt('available', remove: true),
    );
  }
}

class CopiesJsonConverter extends JsonConverter<Copies?, Map<String, dynamic>?> {
  const CopiesJsonConverter();

  @override
  Copies? fromJson(Map<String, dynamic>? json) => Copies.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Copies? copies) => copies?.toJson();
}
