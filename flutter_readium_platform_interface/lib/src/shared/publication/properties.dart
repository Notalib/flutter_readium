// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../publication.dart';

export 'encryption/index.dart';
export 'opds/opds_properties_extension.dart';

/// Set of properties associated with a [Link].
///
/// See https://drafts.opds.io/schema/properties.schema.json
///     https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json
@immutable
class Properties extends AdditionalProperties with Equatable implements JSONable {
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

  static const _unset = Object();

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
  List<Object> get props => [
    additionalProperties,
    contains ?? {},
    page ?? '',
    encryption ?? '',
  ];

  /// (Nullable) Indicates that a resource is encrypted/obfuscated and provides
  /// relevant information for decryption.
  final Encryption? encryption;

  /// Serializes a [Properties] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.of(additionalProperties)
    ..putOpt('page', page?.name)
    ..putIterableIfNotEmpty('contains', contains)
    ..putOpt('orientation', orientation?.name)
    ..putOpt('layout', layout?.name)
    ..putOpt('overflow', overflow?.name)
    ..putOpt('spread', spread?.name)
    ..putOpt('encryption', encryption);

  Properties copyWith({
    Object? page = _unset,
    Object? contains = _unset,
    Object? orientation = _unset,
    Object? layout = _unset,
    Object? overflow = _unset,
    Object? spread = _unset,
    Object? encryption = _unset,
    Object? additionalProperties = _unset,
  }) {
    final mergeProperties = identical(additionalProperties, _unset) || additionalProperties == null
        ? Map<String, dynamic>.of(this.additionalProperties)
        : Map<String, dynamic>.of(this.additionalProperties)
            ..addAll(additionalProperties as Map<String, dynamic>)
            ..removeWhere((key, value) => value == null);

    return Properties(
      page: identical(page, _unset) ? this.page : (page as PresentationPage?)!,
      contains: identical(contains, _unset) ? this.contains : (contains as List<String>?)?.toSet().toList(),
      orientation: identical(orientation, _unset) ? this.orientation : (orientation as PresentationOrientation?)!,
      layout: identical(layout, _unset) ? this.layout : (layout as EpubLayout?)!,
      overflow: identical(overflow, _unset) ? this.overflow : (overflow as PresentationOverflow?)!,
      spread: identical(spread, _unset) ? this.spread : (spread as PresentationSpread?)!,
      encryption: identical(encryption, _unset) ? this.encryption : (encryption as Encryption?)!,
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

    final page = PresentationPage.fromString(
      jsonObject.optNullableString('page', remove: true),
    );
    final contains = jsonObject.optStringsFromArrayOrSingle(
      'contains',
      remove: true,
    );
    final orientation = PresentationOrientation.fromString(
      jsonObject.optNullableString('orientation', remove: true),
    );
    final layout = EpubLayout.fromString(
      jsonObject.optNullableString('layout', remove: true),
    );
    final overflow = PresentationOverflow.fromString(
      jsonObject.optNullableString('overflow', remove: true),
    );
    final spread = PresentationSpread.fromString(
      jsonObject.optNullableString('spread', remove: true),
    );

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
