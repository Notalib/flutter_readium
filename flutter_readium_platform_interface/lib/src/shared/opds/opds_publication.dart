import 'package:dartx/dartx.dart';

import '../../utils/jsonable.dart';
import '../publication/link.dart' show Link;
import '../publication/metadata.dart' show Metadata;

class OpdsPublication implements JSONable {
  OpdsPublication(this.metadata, this.links);

  final Metadata metadata;
  final List<Link> links;

  OpdsPublication copyWith({Metadata? metadata, List<Link>? links}) =>
      OpdsPublication(metadata ?? this.metadata, links ?? this.links);

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson());
    return json;
  }

  static OpdsPublication? fromJson(Map<String, dynamic> json) {
    final metadata = Metadata.fromJson(json['metadata']);
    if (metadata == null) {
      return null;
    }

    final links = Link.fromJSONArray(json['links'] as List<dynamic>?);
    return OpdsPublication(metadata, links);
  }

  static List<OpdsPublication> fromJSONArray(List<dynamic>? jsonArray) {
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
