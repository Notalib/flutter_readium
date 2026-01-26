// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

// ignore_for_file: must_be_immutable

import 'package:equatable/equatable.dart';
import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import '../publication.dart';

/// Set of properties associated with a [Link].
///
/// See https://readium.org/webpub-manifest/schema/properties.schema.json
///     https://readium.org/webpub-manifest/schema/extensions/epub/properties.schema.json
class Properties with EquatableMixin, JSONable, AdditionalProperties {
  Properties({Map<String, dynamic>? additionalProperties}) {
    this.additionalProperties.addAll(additionalProperties ?? {});
  }

  /// (Nullable) Indicates how the linked resource should be displayed in a
  /// reading environment that displays synthetic spreads.
  PresentationPage? get page => PresentationPage.from(additionalProperties.optString('page'));

  /// Identifies content contained in the linked resource, that cannot be
  /// strictly identified using a media type.
  Set<String> get contains => additionalProperties.optStringsFromArrayOrSingle('contains').toSet();

  /// (Nullable) Suggested orientation for the device when displaying the linked
  /// resource.
  PresentationOrientation? get orientation =>
      PresentationOrientation.from(additionalProperties.optString('orientation'));

  /// (Nullable) Hints how the layout of the resource should be presented.
  EpubLayout? get layout => EpubLayout.from(additionalProperties.optString('layout'));

  /// (Nullable) Suggested method for handling overflow while displaying the
  /// linked resource.
  PresentationOverflow? get overflow => PresentationOverflow.from(additionalProperties.optString('overflow'));

  /// (Nullable) Indicates the condition to be met for the linked resource to be
  /// rendered within a synthetic spread.
  PresentationSpread? get spread => PresentationSpread.from(additionalProperties.optString('spread'));

  @override
  List<Object> get props => [additionalProperties];

  /// (Nullable) Indicates that a resource is encrypted/obfuscated and provides
  /// relevant information for decryption.
  Encryption? get encryption {
    if (additionalProperties.containsKey('encrypted') && additionalProperties['encrypted'] is Map<String, dynamic>) {
      return Encryption.fromJSON(additionalProperties['encrypted'] as Map<String, dynamic>);
    }
    return null;
  }

  /// Serializes a [Properties] to its RWPM JSON representation.
  @override
  Map<String, dynamic> toJson() => additionalProperties;

  Properties add(Map<String, dynamic> properties) {
    final props = Map<String, dynamic>.of(additionalProperties)..addAll(properties);
    return Properties(additionalProperties: props);
  }

  Properties copyWit({Map<String, dynamic>? additionalProperties}) =>
      Properties(additionalProperties: additionalProperties ?? this.additionalProperties);

  @override
  String toString() => 'Properties(${toJson()})';

  /// Creates a [Properties] from its RWPM JSON representation.
  static Properties fromJSON(Map<String, dynamic>? json) => Properties(additionalProperties: json ?? {});
}
