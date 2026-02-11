// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

/// The price of a publication in an OPDS link.
///
/// https://drafts.opds.io/schema/properties.schema.json
///
/// @param currency Currency for the price, eg. EUR.
/// @param value Price value, should only be used for display purposes, because of precision issues
///     inherent with Double and the JSON parsing.
@immutable
class Price extends AdditionalProperties with EquatableMixin implements JSONable {
  const Price({required this.currency, required this.value, super.additionalProperties});
  final String currency;
  final double value;

  @override
  List<Object> get props => [currency, value];

  /// Serializes an [Price] to its JSON representation.
  @override
  Map<String, dynamic> toJson() => {...additionalProperties, 'currency': currency, 'value': value};

  /// Creates an [Price] from its JSON representation.
  /// If the price can't be parsed, a warning will be logged with [warnings].
  static Price? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      Fimber.d('Price.fromJSON: null json');
      return null;
    }
    final jsonObject = Map<String, dynamic>.from(json);
    final currency = jsonObject.optNullableString('currency', remove: true);
    final value = jsonObject.optPositiveDouble('value', remove: true);
    if (currency == null || value == null) {
      Fimber.d('Price.fromJSON: invalid currency or value');
      return null;
    }

    return Price(currency: currency, value: value, additionalProperties: jsonObject);
  }
}

class PriceJsonConverter extends JsonConverter<Price?, Map<String, dynamic>?> {
  const PriceJsonConverter();

  @override
  Price? fromJson(Map<String, dynamic>? json) => Price.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Price? price) => price?.toJson();
}
