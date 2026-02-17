// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import '../../../../flutter_readium_platform_interface.dart';

/// Text and data mining
///
/// https://github.com/readium/webpub-manifest/tree/master/contexts/default#text-and-data-mining
class TDM with EquatableMixin implements JSONable {
  const TDM({required this.reservation, this.policy});
  final TDMReservation reservation;
  final String? policy;

  @override
  List<Object?> get props => [reservation, policy];

  @override
  Map<String, dynamic> toJson() => {}
    ..put('reservation', reservation.name)
    ..putOpt('policy', policy);

  static TDM? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final reservation = TDMReservation.fromString(jsonObject.optString('reservation'));
    final policy = jsonObject.optNullableString('policy', remove: true);
    return TDM(reservation: reservation, policy: policy);
  }
}

enum TDMReservation {
  all,
  none;

  factory TDMReservation.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'all':
        return TDMReservation.all;
      case 'none':
      default:
        return TDMReservation.none;
    }
  }
}
