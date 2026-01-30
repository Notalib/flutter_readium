// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../publication.dart';

export 'encryption/index.dart';
export 'opds/opds_properties_extension.dart';

/// Set of properties associated with a [Link].
///
/// See https://drafts.opds.io/schema/properties.schema.json
///     https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json
class Properties extends AdditionalProperties with EquatableMixin implements JSONable {
  const Properties({
    this.page,
    this.contains,
    this.orientation,
    this.layout,
    this.overflow,
    this.spread,
    this.encryption,
    super.additionalProperties,
  });

  /// (Nullable) Indicates how the linked resource should be displayed in a
  /// reading environment that displays synthetic spreads.
  final PresentationPage? page;

  /// Identifies content contained in the linked resource, that cannot be
  /// strictly identified using a media type.
  final List<String>? contains;

  /// (Nullable) Suggested orientation for the device when displaying the linked
  /// resource.
  final PresentationOrientation? orientation;

  /// (Nullable) Hints how the layout of the resource should be presented.
  final EpubLayout? layout;

  /// (Nullable) Suggested method for handling overflow while displaying the
  /// linked resource.
  final PresentationOverflow? overflow;

  /// (Nullable) Indicates the condition to be met for the linked resource to be
  /// rendered within a synthetic spread.
  final PresentationSpread? spread;

  @override
  List<Object> get props => [additionalProperties, contains ?? {}, page ?? '', encryption ?? ''];

  /// (Nullable) Indicates that a resource is encrypted/obfuscated and provides
  /// relevant information for decryption.
  final Encryption? encryption;

  /// Serializes a [Properties] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.of(additionalProperties)
    ..putOpt('page', page)
    ..putIterableIfNotEmpty('contains', contains)
    ..putOpt('orientation', orientation)
    ..putOpt('layout', layout)
    ..putOpt('overflow', overflow)
    ..putOpt('spread', spread)
    ..putOpt('encryption', encryption);

  Properties copyWith({
    PresentationPage? page,
    List<String>? contains,
    PresentationOrientation? orientation,
    EpubLayout? layout,
    PresentationOverflow? overflow,
    PresentationSpread? spread,
    Encryption? encryption,
    Map<String, dynamic>? additionalProperties,
  }) {
    final mergeProperties = Map<String, dynamic>.of(this.additionalProperties)
      ..addAll(additionalProperties ?? {})
      ..removeWhere((key, value) => value == null);

    return Properties(
      page: page ?? this.page,
      contains: contains?.toSet().toList() ?? this.contains,
      orientation: orientation ?? this.orientation,
      layout: layout ?? this.layout,
      overflow: overflow ?? this.overflow,
      spread: spread ?? this.spread,
      encryption: encryption ?? this.encryption,
      additionalProperties: mergeProperties,
    );
  }

  @override
  String toString() => 'Properties(${toJson()})';

  /// Creates a [Properties] from its RWPM JSON representation.
  static Properties fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return Properties();
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final page = PresentationPage.from(jsonObject.optNullableString('page', remove: true));
    final contains = jsonObject.optStringsFromArrayOrSingle('contains', remove: true);
    final orientation = PresentationOrientation.from(jsonObject.optNullableString('orientation', remove: true));
    final layout = EpubLayout.from(jsonObject.optNullableString('layout', remove: true));
    final overflow = PresentationOverflow.from(jsonObject.optNullableString('overflow', remove: true));
    final spread = PresentationSpread.from(jsonObject.optNullableString('spread', remove: true));

    final encryptionMap = jsonObject.optNullableMap('encrypted', remove: true);
    final encryption = Encryption.fromJson(encryptionMap);

    return Properties(
      page: page,
      contains: contains,
      orientation: orientation,
      layout: layout,
      overflow: overflow,
      spread: spread,
      encryption: encryption,
      additionalProperties: jsonObject,
    );
  }
}

class PropertiesJsonConverter extends JsonConverter<Properties?, Map<String, dynamic>?> {
  const PropertiesJsonConverter();

  @override
  Properties? fromJson(Map<String, dynamic>? json) => Properties.fromJson(json);

  @override
  Map<String, dynamic>? toJson(Properties? properties) => properties?.toJson();
}
