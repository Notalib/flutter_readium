// Native (VM) implementation: writes a caller-supplied manifest JSON string to
// a temp file and returns its path, for the audio-recovery integration test.
// Web has no filesystem for this (and the test is native-only), so the
// conditional import below swaps in a throwing stub there.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

Future<String> writeTempAudiobookManifest(String manifestJson) async {
  final dir = await Directory(
    p.join(Directory.systemTemp.path, 'frx_recovery_test'),
  ).create(recursive: true);
  final file = File(p.join(dir.path, 'manifest.json'));
  await file.writeAsString(manifestJson);
  return file.path;
}

/// True if [url]'s host answers at all within [timeout]. Any HTTP response
/// (including 401/403/404) counts as reachable; only a transport failure
/// (connection refused, DNS, TLS, timeout) counts as unreachable. Used to skip
/// the network-dependent auth test when the real host is down, without masking
/// a genuine misclassification when it is up.
Future<bool> isHostReachable(
  String url, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return true;
  } on Object catch (e) {
    // Surface why the precheck failed so the skip reason distinguishes a DNS
    // failure (host not resolvable — e.g. an internal host from an Android
    // emulator) from a timeout or refused connection.
    debugPrint('isHostReachable($url) failed: $e');
    return false;
  } finally {
    client.close(force: true);
  }
}
