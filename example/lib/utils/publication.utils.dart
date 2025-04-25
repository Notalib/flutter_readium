import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/_index.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

class PublicationUtils {
  static String get extractionFolder => 'extracted/files/pubs';

  static Future<void> moveReadiumPublicationsToDocuments() async {
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
      R2Log.d('Asset in pubs: $assetPath');

      final basename = path.basename(assetPath);
      final file = File(path.join(localDir.path, basename));
      final exists = await file.exists();
      R2Log.d('---@ $exists');

      if (!exists) {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes);
        R2Log.d('saved ${file.path} size=${await file.length()}');
      } else {
        R2Log.d('cached ${file.path} size=${await file.length()}');
      }
    }
  }

  static Future<List<OPDSPublication>> loadPublications() async {
    final dirPath = await ReadiumStorage.publicationsDirPath;
    final dir = Directory('$dirPath/local');

    if (await dir.exists()) {
      final pubs = <OPDSPublication>[];
      final entities = dir.listSync();

      for (final entity in entities) {
        final basename = path.basename(entity.path);
        final type = ReadiumDownloader.getMediaType(basename);

        if (type == null) {
          R2Log.e('Unsupported media type: $extension');
          continue;
        }

        try {
          if (entity is File) {
            final basename = path.basename(entity.path);
            Metadata? metaData;
            try {
              metaData = await _populateMetadataFromFile(
                entity,
                path.join(dirPath, '$extractionFolder/$basename'),
              );
            } on Object catch (e) {
              R2Log.w('Error reading metadata: $e');
            }
            metaData ??= Metadata(
              title: {'und': basename},
              identifier: basename.split('.').first,
              language: ['und'],
              author: [
                Contributor.fromJson({
                  'name': {'und': 'Unknown Author'},
                }),
              ],
              xIsAudiobook: false,
              xHasText: true,
            );

            final pub = OPDSPublication(
              images: [],
              links: [Link(href: entity.path, type: type.value)],
              metadata: metaData,
            );
            pubs.add(pub);
          }
        } on Object catch (e) {
          R2Log.e('Error reading file: $e');
        }
      }
      return pubs;
    }
    return [];
  }

  static Future<void> _unpackZipFile(final File zipFile, final String destinationDir) async {
    // Generated using copilot

    // Read the ZIP file as a byte array
    final bytes = await zipFile.readAsBytes();

    // Decode the ZIP file
    final archive = ZipDecoder().decodeBytes(bytes);

    // Extract the contents of the ZIP file
    for (final file in archive) {
      final filename = path.join(destinationDir, file.name);
      if (file.isFile) {
        final data = file.content as List<int>;
        try {
          File(filename)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } on Object catch (e) {
          R2Log.e('error unpacking file: $e');
        }
      } else {
        try {
          Directory(filename).create(recursive: true);
        } on Object catch (e) {
          R2Log.e('error unpacking file: $e');
        }
      }
    }
  }

  static Future<Metadata> _populateMetadataFromFile(
    final File zipFile,
    final String destinationDir,
  ) async {
    await _unpackZipFile(zipFile, destinationDir);

    // look for metadata and manifest files
    final metadataFile = await _locateFile(Directory(destinationDir), 'metadata.xml');
    final package = await _locateFile(Directory(destinationDir), 'package.opf');
    final manifestFile = await _locateFile(Directory(destinationDir), 'manifest.json');

    // Pubs from nota don't have the metadata.xml file
    // Maybe we should consider only supporting manifest.json?
    if (metadataFile != null) {
      return _metadataFromXml(metadataFile);
      // _metadataFromXml(metadataFile); have not been tested with a metadata.xml file as I don't have one
      // it is entirely possible that it does not have "metadata" element which the function expects
    } else if (package != null) {
      return _metadataFromXml(package);
    } else if (manifestFile != null) {
      return _metadataFromJson(manifestFile);
    } else {
      throw ReadiumError(
        'package.opf, metadata.xml, and manifest.json are all missing, invalid file.',
      );
    }
  }

  static Future<File?> _locateFile(final Directory directory, final String filename) async {
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && path.basename(entity.path) == filename) {
        return entity;
      }
    }
    return null;
  }

  static Future<bool> validateFile(final File file) async {
    final publicationsDirPath = await ReadiumStorage.publicationsDirPath;
    final basename = path.basename(file.path);
    final destinationDir = path.join(publicationsDirPath, 'extractionFolder/$basename');
    final localDirPath = path.join(publicationsDirPath, 'local');

    // save file at localDirPath
    final newFile = File(path.join(localDirPath, path.basename(file.path)));
    await file.copy(newFile.path);

    // Check if the file has an allowed extension
    final type = ReadiumDownloader.getMediaType(basename);

    if (type == null) {
      throw ReadiumError('Invalid file type. Please select a valid file.');
    }

    await _unpackZipFile(newFile, destinationDir);

    // look for metadata files
    final metadataFile = await _locateFile(Directory(destinationDir), 'metadata.xml') ??
        await _locateFile(Directory(destinationDir), 'package.opf') ??
        await _locateFile(Directory(destinationDir), 'manifest.json');

    file.delete();

    if (metadataFile == null) {
      newFile.delete();
      throw ReadiumError('Invalid file. missing both manifest.json and metadata.xml.');
    }

    loadPublications();

    return true;
  }

  static Future<void> deletePublication(final OPDSPublication pub) async {
    // TODO: This functions deletes the pub itself. But I believe the unpacked zip file is still in the 'extracted' folder. Should be looked into.
    final href = pub.links.first.href;

    // Create a File object for the href
    final file = File(href);

    // Check if the file exists and delete it if it does
    if (await file.exists()) {
      try {
        await file.delete();
        R2Log.d('Deleted file: $href');
      } on Object catch (e) {
        R2Log.e('Error deleting file: $e');
      }
    } else {
      R2Log.d('File does not exist: $href');
    }
  }

  static Future<Metadata> _metadataFromXml(final File metadataFile) async {
    // the package.opf file from the epub example i have uses Dublin Core Metadata Element Set.
    // Where elements are prefixed with dc: like dc:title, dc:identifier, dc:language, dc:creator
    // the metadata.xml file from the epub example i had did not.
    // which is why we check for both dc: and non dc: elements
    String? title;
    String? identifier;
    String? language;
    String? author;
    var hasAudio = false;
    var hasText = false;
    final xmlString = await metadataFile.readAsString();
    final document = xml.XmlDocument.parse(xmlString);
    final metadata = document.findAllElements('metadata').first;

    try {
      final titleElement = metadata.findElements('title').isNotEmpty
          ? metadata.findElements('title').first
          : metadata.findElements('dc:title').first;
      // ignore: deprecated_member_use
      title = titleElement.value ?? titleElement.text;
    } on Object catch (e) {
      R2Log.e('error reading title: $e');
    }

    try {
      final identifierElement = metadata.findElements('identifier').isNotEmpty
          ? metadata.findElements('identifier').first
          : metadata.findElements('dc:identifier').first;
      // ignore: deprecated_member_use
      identifier = identifierElement.value ?? identifierElement.text;
    } on Object catch (e) {
      R2Log.e('Error reading identifier: $e');
    }

    try {
      final authorElement = metadata.findElements('author').isNotEmpty
          ? metadata.findElements('author').first
          : metadata.findElements('dc:creator').first;
      // ignore: deprecated_member_use
      author = authorElement.value ?? authorElement.text;
    } on Object catch (e) {
      R2Log.e('Error reading identifier: $e');
    }

    hasAudio = await _hasMimeTypeEpub(metadata, 'audio');
    hasText = await _hasMimeTypeEpub(metadata, 'text');

    try {
      final languageElement = metadata.findElements('language').isNotEmpty
          ? metadata.findElements('language').first
          : metadata.findElements('dc:language').first;

      // ignore: deprecated_member_use
      language = languageElement.value ?? languageElement.text;
    } on Object catch (e) {
      R2Log.e('Error reading language: $e');
    }

    final languages = <String>[language ?? 'en'];
    return Metadata(
      title: {language ?? 'en': title ?? ''},
      language: languages,
      author: [
        Contributor.fromJson(
          {
            'name': {language ?? 'und': author ?? 'Unknown Author'},
          },
        ),
      ],
      identifier: identifier ?? '',
      xHasText: hasText,
      xIsAudiobook: hasAudio,
    );
  }

  static Future<Metadata> _metadataFromJson(final File manifestFile) async {
    String? title;
    String? identifier;
    String? language;
    String? author;
    var hasAudio = false;
    var hasText = false;
    // Read and parse the JSON file
    final jsonString = await manifestFile.readAsString();
    final manifest = json.decode(jsonString);
    final metadata = manifest['metadata'];

    // Extract information from the JSON and populate pub.metadata
    try {
      title = metadata['title'];
    } on Object catch (e) {
      R2Log.e('Error reading title: $e');
    }

    try {
      identifier = metadata['identifier'];
    } on Object catch (e) {
      R2Log.e('Error reading identifier: $e');
    }

    try {
      author = metadata['author'];
    } on Object catch (e) {
      R2Log.e('Error reading author: $e');
    }

    try {
      language = metadata['language'];
    } on Object catch (e) {
      R2Log.e('Error reading language: $e');
    }

    hasAudio = await _hasMimeTypeWebpub(manifest, 'audio');
    hasText = await _hasMimeTypeWebpub(manifest, 'text');

    final languages = <String>[language ?? 'en'];
    R2Log.d('printing metadata $identifier');
    return Metadata(
      title: {language ?? 'und': title ?? ''},
      author: [
        Contributor.fromJson(
          {
            'name': {language ?? 'und': author ?? 'Unknown Author'},
          },
        ),
      ],
      language: languages,
      identifier: identifier ?? '',
      xHasText: hasText,
      xIsAudiobook: hasAudio,
    );
  }

  static Future<bool> _hasMimeTypeWebpub(
    final Map<String, dynamic> manifest,
    final String mimeType,
  ) async {
    // generated using copilot, with minor modifications
    try {
      // Check the resources array for audio MIME types
      if (manifest.containsKey('resources')) {
        final resources = manifest['resources'] as List<dynamic>;
        for (final resource in resources) {
          if (resource is Map<String, dynamic> && resource.containsKey('type')) {
            final type = resource['type'] as String;
            if (type.startsWith('$mimeType/')) {
              return true; // Audio resource found
            }
          }
        }
      }
    } on Object catch (e) {
      R2Log.d('Error reading manifest.json: $e');
    }
    return false; // No audio resources found
  }

  static Future<bool> _hasMimeTypeEpub(final XmlElement metadata, final String mimeType) async {
    // generated using copilot, with minor modifications
    try {
      // Check the manifest for audio MIME types
      for (final item in metadata.findElements('item')) {
        final mediaType = item.getAttribute('media-type');
        if (mediaType != null && mediaType.startsWith('$mimeType/')) {
          return true; // Audio resource found
        }
      }
    } on Object catch (e) {
      R2Log.e('Error reading EPUB file: $e');
    }
    return false; // No audio resources found
  }
}
