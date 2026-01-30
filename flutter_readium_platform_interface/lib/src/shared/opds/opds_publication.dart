import 'package:dartx/dartx.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../utils/jsonable.dart';
import '../publication/link.dart' show Link;
import '../publication/metadata.dart' show Metadata;

class OpdsPublication implements JSONable {
  const OpdsPublication(this.metadata, this.links, {this.images = const []});

  final Metadata metadata;
  final List<Link> links;
  final List<Link> images;

  OpdsPublication copyWith({Metadata? metadata, List<Link>? links, List<Link>? images}) =>
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

    final metadata = Metadata.fromJson(jsonObject.optNullableMap('metadata', remove: true));
    if (metadata == null) {
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

  @override
  OpdsPublication fromJson(Map<String, dynamic> json) => OpdsPublication.fromJson(json)!;

  @override
  Map<String, dynamic> toJson(OpdsPublication publication) => publication.toJson();
}
