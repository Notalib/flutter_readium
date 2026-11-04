import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

final _log = Logger('DeviceFileImporter');

/// Extensions the Readium toolkits can open as self-contained publications.
/// Deliberately excludes bare `manifest.json`/`.zip`: their resources only
/// resolve relative to a served origin, not from a picked file on disk.
const supportedPublicationExtensions = [
  'epub',
  'pdf',
  'webpub',
  'audiobook',
  'divina',
  'cbz',
];

/// Thrown when the user picks a file whose extension is not a supported
/// publication format.
class UnsupportedFormatException implements Exception {
  const UnsupportedFormatException(this.fileName);

  final String fileName;

  @override
  String toString() => 'Unsupported file format: $fileName';
}

/// Opens the OS file picker and returns a URL for a publication that can be
/// handed straight to `loadPublication`/`openPublication` without copying the
/// file into app storage.
///
/// Returns `null` when the user cancels; throws [UnsupportedFormatException]
/// for unsupported extensions.
class DeviceFileImporter {
  const DeviceFileImporter._();

  static Future<String?> pickPublicationUrl() async {
    // FileType.any on purpose: `webpub`/`audiobook` have no registered UTType
    // on iOS, so FileType.custom would grey out (or hide) exactly the files we
    // want. Extension validation happens below instead.
    final file = await FilePicker.pickFile(
      type: FileType.any,
      // Android: persist the SAF read grant so the content:// URI stays
      // readable across app restarts; the bookshelf persists the URL itself.
      // iOS ignores this (the document picker hands over a file copy).
      androidOptions: const FilePickerAndroidOptions(
        safOptions: AndroidSAFOptions(grant: AndroidSAFGrant.lifetime),
      ),
    );
    if (file == null) {
      _log.info('User canceled the file picker');
      return null;
    }

    final extension = path.extension(file.name).replaceFirst('.', '').toLowerCase();
    if (!supportedPublicationExtensions.contains(extension)) {
      throw UnsupportedFormatException(file.name);
    }

    // Android: `path` is null for SAF picks and `uri` is the content:// URL —
    // the plugin's AssetRetriever reads it through its contentResolver.
    // iOS/desktop: a real file path in app-owned temp storage.
    final url = file.path ?? file.uri.toString();
    _log.info('Picked publication: $url');
    return url;
  }

  /// Whether [url] points at a still-accessible picked publication. iOS temp
  /// files can be purged by the OS, so persisted entries are probed before
  /// loading; SAF grants are assumed intact (loadPublication surfaces the
  /// error if one was revoked).
  static Future<bool> isStillAvailable(String url) async {
    if (kIsWeb || url.startsWith('content://') || url.startsWith('http')) {
      return true;
    }
    return File(url).exists();
  }
}
