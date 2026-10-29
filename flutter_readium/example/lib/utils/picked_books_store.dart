import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'readium_storage.dart';

final _log = Logger('PickedBooksStore');

/// Persists the URLs of publications picked from the device with the file
/// picker. Those books are opened in place — never copied into app storage —
/// so only their URLs are remembered:
/// * Android: SAF `content://` URIs, kept readable across app restarts thanks
///   to the persistable URI grant taken at pick time.
/// * iOS: a path in the app's temporary directory (the document picker hands
///   over a copy the app owns); the OS may purge it, in which case the entry
///   is dropped again on the next load.
class PickedBooksStore {
  const PickedBooksStore._();

  static const _fileName = 'picked_books.json';

  static Future<File> _storeFile() async {
    final root = await ReadiumStorage.rootDir;
    return File(path.join(root.path, _fileName));
  }

  static Future<List<String>> load() async {
    try {
      final file = await _storeFile();
      if (!await file.exists()) return [];
      final decoded = json.decode(await file.readAsString());
      return decoded is List ? decoded.whereType<String>().toList() : [];
    } on Object catch (e) {
      _log.warning('Failed to read picked books store: $e');
      return [];
    }
  }

  static Future<void> _save(List<String> urls) async {
    final file = await _storeFile();
    await file.writeAsString(json.encode(urls));
  }

  static Future<void> add(String url) async {
    final urls = await load();
    if (urls.contains(url)) return;
    urls.add(url);
    await _save(urls);
  }

  static Future<void> remove(String url) async {
    final urls = await load();
    if (urls.remove(url)) {
      await _save(urls);
    }
  }
}
