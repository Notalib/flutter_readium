// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../extensions/strings.dart';
import '../../utils/jsonable.dart';

/// Indicated the availability of a given resource.
///
/// https://drafts.opds.io/schema/properties.schema.json
///
/// @param since Timestamp for the previous state change.
/// @param until Timestamp for the next state change.
@immutable
class Availability with EquatableMixin implements JSONable {
  const Availability({required this.state, this.since, this.until});
  final AvailabilityState state;
  final DateTime? since;
  final DateTime? until;

  @override
  List<Object?> get props => [state, since, until];

  /// Serializes an [Availability] to its JSON representation.
  @override
  Map<String, dynamic> toJson() => {}
    ..put('state', state.name)
    ..putOpt('since', since?.toIso8601String())
    ..putOpt('until', until?.toIso8601String());

  /// Creates an [Availability] from its JSON representation.
  /// If the availability can't be parsed, a warning will be logged with [warnings].
  static Availability? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final state = AvailabilityState.fromString(jsonObject.optNullableString('state', remove: true));
    if (state == null) {
      return null;
    }
    final since = jsonObject.optNullableString('since', remove: true)?.iso8601ToDate();
    final until = jsonObject.optNullableString('until', remove: true)?.iso8601ToDate();

    return Availability(state: state, since: since, until: until);
  }
}

enum AvailabilityState {
  available('available'),
  unavailable('unavailable'),
  reserved('reserved'),
  ready('ready');

  const AvailabilityState(this.name);
  final String name;

  static AvailabilityState? fromString(String? value) =>
      AvailabilityState.values.firstWhereOrNull((state) => state.name == value);
}

class AvailabilityJsonConverter extends JsonConverter<Availability?, Map<String, dynamic>?> {
  const AvailabilityJsonConverter();

  @override
  Availability? fromJson(Map<String, dynamic>? json) => Availability.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Availability? availability) => availability?.toJson();
}
