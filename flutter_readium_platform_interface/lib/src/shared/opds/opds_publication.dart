import '../../commons/utils/jsonable.dart';
import '../publication/link.dart' show Link;
import '../publication/metadata.dart' show Metadata;

class OpdsPublication implements JSONable {
  OpdsPublication(this.metadata, this.links);

  Metadata metadata;
  List<Link> links;

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{}
      ..putJSONableIfNotEmpty('metadata', metadata)
      ..put('links', links.toJson());
    return json;
  }
}
