import 'package:dartx/dartx.dart';
import 'package:fimber/fimber.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../../../flutter_readium_platform_interface.dart';

@immutable
class OpdsPublication implements JSONable {
  const OpdsPublication(this.metadata, this.links, {this.images = const []});

  final OpdsMetadata metadata;
  final List<Link> links;
  final List<Link> images;

  static final FimberLog _logger = FimberLog('OpdsPublication');

  OpdsPublication copyWith({OpdsMetadata? metadata, List<Link>? links, List<Link>? images}) =>
      OpdsPublication(metadata ?? this.metadata, links ?? this.links, images: images ?? this.images);

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

    final metadata = OpdsMetadata.fromJson(jsonObject.optNullableMap('metadata', remove: true));
    if (metadata == null) {
      _logger.w('OpdsPublication metadata is null, cannot parse publication');
      return null;
    }

    final links = Link.fromJsonArray(jsonObject.optJsonArray('links', remove: true));
    final images = Link.fromJsonArray(jsonObject.optJsonArray('images', remove: true));
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

class OpdsPublicationJsonConverter extends JsonConverter<OpdsPublication, Map<String, dynamic>> {
  const OpdsPublicationJsonConverter();

  static final FimberLog _logger = FimberLog('OpdsPublicationJsonConverter');

  @override
  OpdsPublication fromJson(Map<String, dynamic> json) {
    final publication = OpdsPublication.fromJson(json);
    if (publication == null) {
      _logger.w('Received null OpdsPublication from JSON, creating dummy.');
      return OpdsPublication(OpdsMetadata(localizedTitle: LocalizedString()), [], images: []);
    }
    return publication;
  }

  @override
  Map<String, dynamic> toJson(OpdsPublication publication) => publication.toJson();
}

class OpdsPublicationNullableJsonConverter extends JsonConverter<OpdsPublication?, Map<String, dynamic>?> {
  const OpdsPublicationNullableJsonConverter();

  @override
  OpdsPublication? fromJson(Map<String, dynamic>? json) => OpdsPublication.fromJson(json);

  @override
  Map<String, dynamic>? toJson(OpdsPublication? publication) => publication?.toJson();
}
