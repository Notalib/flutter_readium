// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/jsonable.dart';

@immutable
class Drm with EquatableMixin implements JSONable {
  factory Drm.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return lcp;
    }

    final jsonObject = Map<String, dynamic>.of(json);
    final brand = jsonObject.optNullableString('brand', remove: true);
    final scheme = jsonObject.optNullableString('scheme', remove: true);

    if (brand == null || scheme == null) {
      return lcp;
    }

    return Drm._(brand, scheme);
  }

  const Drm._(this.brand, this.scheme);
  static const Drm lcp = Drm._('lcp', 'http://readium.org/2014/01/lcp');
  final String brand;
  final String scheme;

  @override
  List<Object?> get props => [brand, scheme];

  @override
  String toString() => 'Drm{brand: $brand, scheme: $scheme}';

  @override
  toJson() => <String, dynamic>{}
    ..put('brand', brand)
    ..put('scheme', scheme);
}
