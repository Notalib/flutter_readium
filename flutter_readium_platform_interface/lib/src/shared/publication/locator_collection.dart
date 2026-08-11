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
class LocatorCollection with Equatable implements JSONable {
  const LocatorCollection({
    this.metadata = const LocatorCollectionMetadata(),
    this.links = const [],
    this.locators = const [],
  });

  static const _unset = Object();

  final LocatorCollectionMetadata metadata;
  final List<Link> links;
  final List<Locator> locators;

  static LocatorCollection? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final metadata = LocatorCollectionMetadata.fromJson(
      jsonObject['metadata'] as Map<String, dynamic>?,
    );

    final linksJson = jsonObject['links'] as List<dynamic>?;
    final links = linksJson?.map((e) => Link.fromJson(e as Map<String, dynamic>?)).whereType<Link>().toList() ?? [];

    final locatorsJson = jsonObject['locators'] as List<dynamic>?;
    final locators =
        locatorsJson?.map((e) => Locator.fromJson(e as Map<String, dynamic>?)).whereType<Locator>().toList() ?? [];

    return LocatorCollection(
      metadata: metadata,
      links: links,
      locators: locators,
    );
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

  LocatorCollection copyWith({
    Object? metadata = _unset,
    Object? links = _unset,
    Object? locators = _unset,
  }) => LocatorCollection(
    metadata: identical(metadata, _unset) ? this.metadata : (metadata as LocatorCollectionMetadata?)!,
    links: identical(links, _unset) ? this.links : (links as List<Link>?)!,
    locators: identical(locators, _unset) ? this.locators : (locators as List<Locator>?)!,
  );

  @override
  List<Object?> get props => [metadata, links, locators];

  @override
  String toString() => 'LocatorCollection{metadata: $metadata, links: $links, locators: $locators}';
}

/// Holds the metadata of a [LocatorCollection].
@immutable
class LocatorCollectionMetadata extends AdditionalProperties with Equatable implements JSONable {
  const LocatorCollectionMetadata({
    this.localizedTitle,
    this.numberOfItems,
    super.additionalProperties,
  });

  static const _unset = Object();

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
    final numberOfItems = jsonObject.optNullableInt(
      'numberOfItems',
      remove: true,
    );

    // Validate numberOfItems is positive
    final validNumberOfItems = (numberOfItems != null && numberOfItems >= 0) ? numberOfItems : null;

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
    Object? localizedTitle = _unset,
    Object? numberOfItems = _unset,
    Object? additionalProperties = _unset,
  }) => LocatorCollectionMetadata(
    localizedTitle: identical(localizedTitle, _unset) ? this.localizedTitle : localizedTitle,
    numberOfItems: identical(numberOfItems, _unset) ? this.numberOfItems : (numberOfItems as int?)!,
    additionalProperties: identical(additionalProperties, _unset) || additionalProperties == null
        ? this.additionalProperties
        : (additionalProperties as Map<String, dynamic>),
  );

  @override
  List<Object?> get props => [
    localizedTitle,
    numberOfItems,
    additionalProperties,
  ];

  @override
  String toString() =>
      'LocatorCollectionMetadata{title: $title, numberOfItems: $numberOfItems, '
      'otherMetadata: $additionalProperties}';
}
