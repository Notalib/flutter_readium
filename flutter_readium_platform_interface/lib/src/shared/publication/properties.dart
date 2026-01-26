// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import '../../utils/jsonable.dart';
import '../publication.dart';

/// Set of properties associated with a [Link].
///
/// See https://readium.org/webpub-manifest/schema/properties.schema.json
///     https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json
class Properties with EquatableMixin, JSONable {
  Properties({Map<String, dynamic>? otherProperties}) : otherProperties = otherProperties ?? {};

  /// (Nullable) Indicates how the linked resource should be displayed in a
  /// reading environment that displays synthetic spreads.
  PresentationPage? get page => PresentationPage.from(otherProperties.optString('page'));

  /// Identifies content contained in the linked resource, that cannot be
  /// strictly identified using a media type.
  Set<String> get contains => otherProperties.optStringsFromArrayOrSingle('contains').toSet();

  /// (Nullable) Suggested orientation for the device when displaying the linked
  /// resource.
  PresentationOrientation? get orientation => PresentationOrientation.from(otherProperties.optString('orientation'));

  /// (Nullable) Hints how the layout of the resource should be presented.
  EpubLayout? get layout => EpubLayout.from(otherProperties.optString('layout'));

  /// (Nullable) Suggested method for handling overflow while displaying the
  /// linked resource.
  PresentationOverflow? get overflow => PresentationOverflow.from(otherProperties.optString('overflow'));

  /// (Nullable) Indicates the condition to be met for the linked resource to be
  /// rendered within a synthetic spread.
  PresentationSpread? get spread => PresentationSpread.from(otherProperties.optString('spread'));

  Map<String, dynamic> otherProperties;

  @override
  List<Object> get props => [otherProperties];

  dynamic operator [](String name) => otherProperties[name];

  /// (Nullable) Indicates that a resource is encrypted/obfuscated and provides
  /// relevant information for decryption.
  Encryption? get encryption {
    if (otherProperties.containsKey('encrypted') && otherProperties['encrypted'] is Map<String, dynamic>) {
      return Encryption.fromJSON(otherProperties['encrypted'] as Map<String, dynamic>);
    }
    return null;
  }

  /// Serializes a [Properties] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => otherProperties;

  Properties add(Map<String, dynamic> properties) {
    final props = Map<String, dynamic>.of(otherProperties)..addAll(properties);
    return Properties(otherProperties: props);
  }

  Properties copyWit({Map<String, dynamic>? otherProperties}) =>
      Properties(otherProperties: otherProperties ?? this.otherProperties);

  @override
  String toString() => 'Properties(${toJson()})';

  /// Creates a [Properties] from its RWPM JSON representation.
  static Properties fromJSON(Map<String, dynamic>? json) => Properties(otherProperties: json ?? {});
}
