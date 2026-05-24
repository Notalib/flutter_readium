// Native (iOS/Android) fixture loader — copies asset publications to local
// storage and returns their file paths.

import 'package:flutter_readium_example/utils/publication_utils.dart';
import 'package:path/path.dart' as p;

Future<Map<String, String>> loadFixturePaths() async {
  final pubs = await PublicationUtils.moveAssetPublicationsToReadiumStorage();
  return {for (final pub in pubs) p.basename(pub): pub};
}
