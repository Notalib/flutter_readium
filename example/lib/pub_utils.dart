import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import 'readium_storage.dart';

class PublicationUtils {
  static Future<void> listAssetPubFiles() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final pubAssets =
        manifestMap.keys.where((final assetPath) => assetPath.startsWith('assets/pubs/'));

    for (final pub in pubAssets) {
      debugPrint(pub);
    }
  }

  static Future<void> moveTestPublicationsToReadiumStorage() async {
    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;
    final localDirPath = path.join(publicationsDirPath, 'local');

    // Create the local directory if it doesn't exist
    final localDir = Directory(localDirPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }
    // Load the AssetManifest.json file and find all assets in the 'assets/pubs' directory
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final pubsAssets =
        manifestMap.keys.where((final assetPath) => assetPath.startsWith('assets/pubs/'));

    // Loop through the filtered assets
    for (final assetPath in pubsAssets) {
      debugPrint('Asset in pubs: $assetPath');

      final basename = path.basename(assetPath);
      final file = File(path.join(localDir.path, basename));
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
