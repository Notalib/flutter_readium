// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../../utils/additional_properties.dart';
import '../../utils/jsonable.dart';
import 'link.dart';
import 'locator.dart';

/// Represents a sequential list of [Locator] objects.
///
/// For example, a search result or a list of positions.
@immutable
class LocatorCollection with EquatableMixin implements JSONable {
  const LocatorCollection({
    this.metadata = const LocatorCollectionMetadata(),
    this.links = const [],
    this.locators = const [],
  });

  final LocatorCollectionMetadata metadata;
  final List<Link> links;
  final List<Locator> locators;

  static LocatorCollection? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final metadata = LocatorCollectionMetadata.fromJson(jsonObject['metadata'] as Map<String, dynamic>?);

    final linksJson = jsonObject['links'] as List<dynamic>?;
    final links = linksJson?.map((e) => Link.fromJson(e as Map<String, dynamic>?)).whereType<Link>().toList() ?? [];

    final locatorsJson = jsonObject['locators'] as List<dynamic>?;
    final locators =
        locatorsJson?.map((e) => Locator.fromJson(e as Map<String, dynamic>?)).whereType<Locator>().toList() ?? [];

    return LocatorCollection(metadata: metadata, links: links, locators: locators);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    final metadataJson = metadata.toJson();
    if (metadataJson.isNotEmpty) {
      json['metadata'] = metadataJson;
    }

    if (links.isNotEmpty) {
      json['links'] = links.map((e) => e.toJson()).toList();
    }

    json['locators'] = locators.map((e) => e.toJson()).toList();

    return json;
  }

  LocatorCollection copyWith({LocatorCollectionMetadata? metadata, List<Link>? links, List<Locator>? locators}) =>
      LocatorCollection(
        metadata: metadata ?? this.metadata,
        links: links ?? this.links,
        locators: locators ?? this.locators,
      );

  @override
  List<Object?> get props => [metadata, links, locators];

  @override
  String toString() => 'LocatorCollection{metadata: $metadata, links: $links, locators: $locators}';
}

/// Holds the metadata of a [LocatorCollection].
@immutable
class LocatorCollectionMetadata extends AdditionalProperties with EquatableMixin implements JSONable {
  const LocatorCollectionMetadata({this.localizedTitle, this.numberOfItems, super.additionalProperties});

  /// The localized title. Can be a simple string or a map of language codes to strings.
  final dynamic localizedTitle;

  /// Indicates the total number of locators in the collection.
  final int? numberOfItems;

  /// Returns the title as a simple string.
  String? get title {
    if (localizedTitle == null) {
      return null;
    }
    if (localizedTitle is String) {
      return localizedTitle as String;
    }
    if (localizedTitle is Map) {
      final map = localizedTitle as Map;
      // Return the first available value or the 'en' value if available
      if (map.containsKey('en')) {
        return map['en'] as String?;
      }
      return map.values.firstOrNull as String?;
    }
    return null;
  }

  static LocatorCollectionMetadata fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const LocatorCollectionMetadata();
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final localizedTitle = jsonObject.remove('title');
    final numberOfItems = jsonObject.optNullableInt('numberOfItems', remove: true);

    // Validate numberOfItems is positive
    final validNumberOfItems = (numberOfItems != null && numberOfItems > 0) ? numberOfItems : null;

    return LocatorCollectionMetadata(
      localizedTitle: localizedTitle,
      numberOfItems: validNumberOfItems,
      additionalProperties: jsonObject,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = Map<String, dynamic>.of(additionalProperties);

    if (localizedTitle != null) {
      json['title'] = localizedTitle;
    }

    if (numberOfItems != null) {
      json['numberOfItems'] = numberOfItems;
    }

    return json;
  }

  LocatorCollectionMetadata copyWith({
    dynamic localizedTitle,
    int? numberOfItems,
    Map<String, dynamic>? additionalProperties,
  }) => LocatorCollectionMetadata(
    localizedTitle: localizedTitle ?? this.localizedTitle,
    numberOfItems: numberOfItems ?? this.numberOfItems,
    additionalProperties: additionalProperties ?? this.additionalProperties,
  );

  @override
  List<Object?> get props => [localizedTitle, numberOfItems, additionalProperties];

  @override
  String toString() =>
      'LocatorCollectionMetadata{title: $title, numberOfItems: $numberOfItems, '
      'otherMetadata: $additionalProperties}';
}
