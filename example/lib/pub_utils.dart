import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import 'readium_storage.dart';

class PublicationUtils {
  static Future<Iterable<String>> getAssetPubFiles() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final pubAssets =
        manifestMap.keys.where((final assetPath) => assetPath.startsWith('assets/pubs/'));
    return pubAssets;
  }

  static Future<void> moveTestPublicationsToReadiumStorage() async {
    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;

    // Create the local directory if it doesn't exist
    final pubsDir = Directory(publicationsDirPath);
    if (!await pubsDir.exists()) {
      await pubsDir.create(recursive: true);
    }
    // Load the AssetManifest.json file and find all assets in the 'assets/pubs' directory
    final pubAssets = await getAssetPubFiles();

    // Loop through the filtered assets
    for (final assetPath in pubAssets) {
      debugPrint('Asset in pubs: $assetPath');

      final basename = path.basename(assetPath);
      final file = File(path.join(pubsDir.path, basename));
      final exists = await file.exists();
      debugPrint('${file.path} already exists? $exists');

      if (!exists) {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes);
        debugPrint('saved ${file.path} size=${await file.length()}');
      } else {
        debugPrint('cached ${file.path} size=${await file.length()}');
      }
    }
  }
}
