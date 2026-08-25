import 'package:dartx/dartx.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

@immutable
class OpdsPublication implements JSONable {
  const OpdsPublication(this.metadata, this.links, {this.images = const []});

  final OpdsMetadata metadata;
  final List<Link> links;
  final List<Link> images;

  OpdsPublication copyWith({
    Object? metadata = unset,
    Object? links = unset,
    Object? images = unset,
  }) => OpdsPublication(
    identical(metadata, unset) ? this.metadata : (metadata as OpdsMetadata?)!,
    identical(links, unset) ? this.links : (links as List<Link>?)!,
    images: identical(images, unset) ? this.images : (images as List<Link>?)!,
  );

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..putIterableIfNotEmpty('links', links.toJson())
      ..putIterableIfNotEmpty('images', images.toJson());
    return json;
  }

  static OpdsPublication? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final jsonObject = Map<String, dynamic>.of(json);

    final metadata = OpdsMetadata.fromJson(
      jsonObject.optNullableMap('metadata', remove: true),
    );
    if (metadata == null) {
      ReadiumLog.w(
        'OpdsPublication metadata is null, cannot parse publication',
      );
      return null;
    }

    final links = Link.fromJsonArray(
      jsonObject.optJsonArray('links', remove: true),
    );
    final images = Link.fromJsonArray(
      jsonObject.optJsonArray('images', remove: true),
    );
    return OpdsPublication(metadata, links, images: images);
  }

  static List<OpdsPublication> fromJsonArray(List<dynamic>? jsonArray) {
    if (jsonArray == null) {
      return [];
    }

    return jsonArray.mapNotNull((json) {
      if (json is Map<String, dynamic>) {
        return OpdsPublication.fromJson(json);
      }
      return null;
    }).toList();
  }
}
