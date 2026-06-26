import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'readium_storage.dart';

final _log = Logger('PublicationUtils');

class PublicationUtils {
  static Future<Iterable<String>> getAssetPubFiles() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest.listAssets().where(
      (asset) => asset.startsWith('assets/pubs/'),
    );
    return assets;
  }

  static Future<List<String>> moveAssetPublicationsToReadiumStorage() async {
    if (kIsWeb) {
      _log.warning('moveAssetPublicationsToReadiumStorage is not supported on web');
      return <String>[];
    }

    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;

    // Create the local directory if it doesn't exist
    final pubsDir = Directory(publicationsDirPath);
    if (!await pubsDir.exists()) {
      await pubsDir.create(recursive: true);
    }
    // Load the AssetManifest.json file and find all assets in the 'assets/pubs' directory
    final pubAssets = await getAssetPubFiles();
    final pubs = <String>[];

    final allowedExts = [
      '.webpub',
      '.epub',
      '.audiobook',
      '.pdf',
      '.zip',
      '.json',
    ];

    // Loop through the filtered assets
    for (final assetPath in pubAssets) {
      if (!allowedExts.any((ext) => assetPath.endsWith(ext))) {
        _log.fine('Skip asset path: $assetPath');
        continue;
      }
      _log.fine('Asset in pubs: $assetPath');

      final basename = path.basename(assetPath);
      final file = File(path.join(pubsDir.path, basename));
      final exists = await file.exists();
      _log.fine('${file.path} already exists? $exists');

      if (!exists) {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await file.writeAsBytes(bytes);
        _log.info('saved ${file.path} size=${await file.length()}');
      } else {
        _log.fine('cached ${file.path} size=${await file.length()}');
      }
      pubs.add(file.path);
    }
    return pubs;
  }

  static Future<String> copyFileToReadiumPubStorage(File file) async {
    if (kIsWeb) {
      throw UnsupportedError('copyFileToReadiumPubStorage is not supported on web');
    }

    final exists = await file.exists();
    if (!exists) {
      _log.warning('Could not copy file from ${file.path}, does not exist');
    }

    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;
    String newPath = path.join(publicationsDirPath, file.uri.path);
    await file.copy(newPath);
    _log.info(
      'copied file ${file.path} size=${await file.length()} to=$newPath',
    );
    return newPath;
  }

  static Future<void> removePublicationFromReadiumStorage(
    String pubPath,
  ) async {
    if (kIsWeb) {
      _log.warning('removePublicationFromReadiumStorage is not supported on web');
      return;
    }

    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;
    final publicationPath = path.join(publicationsDirPath, pubPath);
    await File(publicationPath).delete();
  }
}
